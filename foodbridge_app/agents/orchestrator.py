"""Orchestrator: runs the four agents in a safe order every cycle.
  freshness -> matching -> pickup -> notification
Each agent runs in its own transaction, so one failure never blocks the others.
A Postgres advisory lock makes sure only ONE worker runs a cycle even with many uvicorn workers."""
import logging
import time

from sqlalchemy import text

from ..config import settings
from ..database import SessionLocal, engine
from ..services.db_calls import expire_old_donations
from . import freshness_agent, matching_agent, notification_agent, pickup_agent, llm

logger = logging.getLogger("foodbridge.agents")
LOCK_KEY = 727301
AGENTS = [
    ("freshness", freshness_agent.sweep),
    ("matching", matching_agent.sweep),
    ("pickup", pickup_agent.sweep),
    ("notification", notification_agent.sweep),
]
STATE: dict = {"last_run": None, "last_result": None, "cycles": 0}


def run_cycle(trigger: str = "loop") -> dict:
    result: dict = {"trigger": trigger, "skipped": False, "agents": {}, "errors": {}}
    t0 = time.time()
    with engine.connect() as lock:
        got = lock.execute(text("SELECT pg_try_advisory_lock(:k)"), {"k": LOCK_KEY}).scalar()
        if not got:
            result["skipped"] = True
            return result
        try:
            db = SessionLocal()
            try:
                expire_old_donations(db)  # keep the original expiry sweep
                db.commit()
            except Exception as exc:
                db.rollback()
                logger.warning("expire_old_donations failed: %s", exc)
            finally:
                db.close()

            for name, fn in AGENTS:
                db = SessionLocal()
                try:
                    result["agents"][name] = fn(db)
                    db.commit()
                except Exception as exc:  # isolate failures per agent
                    db.rollback()
                    result["errors"][name] = str(exc)[:300]
                    logger.exception("agent %s failed", name)
                finally:
                    db.close()
        finally:
            lock.execute(text("SELECT pg_advisory_unlock(:k)"), {"k": LOCK_KEY})
            lock.commit()

    result["seconds"] = round(time.time() - t0, 2)
    result["llm_enabled"] = llm.enabled()
    STATE.update(last_run=time.time(), last_result=result, cycles=STATE["cycles"] + 1)
    if any(result["agents"].values()):
        logger.info("agent cycle: %s", result["agents"])
    return result


def after_donation_created(donation_id: int) -> None:
    """Background task right after a donation is posted: explain the matches + safety-review it."""
    db = SessionLocal()
    try:
        matching_agent.explain(db, donation_id)
        freshness_agent.safety_review(db, donation_id)
        db.commit()
    except Exception as exc:
        db.rollback()
        logger.warning("post-create agent work failed: %s", exc)
    finally:
        db.close()
