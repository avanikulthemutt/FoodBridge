"""Agent endpoints: admin control/visibility + donor-facing AI trace."""
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import text
from sqlalchemy.orm import Session

from ..agents import llm, matching_agent, orchestrator
from ..config import settings
from ..database import get_db
from ..deps import get_current_user, get_profile_id, require_role

router = APIRouter(prefix="/api", tags=["agents"])


@router.get("/agents/status")
def agents_status(user: dict = Depends(require_role("admin")), db: Session = Depends(get_db)):
    counts = db.execute(text("""
        SELECT agent, COUNT(*) AS actions_24h, COUNT(*) FILTER (WHERE used_llm) AS llm_actions
          FROM agent_actions WHERE created_at > NOW() - INTERVAL '24 hours'
         GROUP BY agent ORDER BY agent""")).mappings().all()
    return {"enabled": settings.AGENTS_ENABLED, "llm_enabled": llm.enabled(),
            "model": settings.AGENT_MODEL if llm.enabled() else None,
            "cycle_seconds": settings.AGENT_CYCLE_SECONDS,
            "cycles_run": orchestrator.STATE["cycles"],
            "last_result": orchestrator.STATE["last_result"],
            "last_24h": [dict(c) for c in counts]}


@router.post("/agents/run")
def agents_run_now(user: dict = Depends(require_role("admin"))):
    """Run one full agent cycle immediately (handy for demos)."""
    return orchestrator.run_cycle("manual")


@router.get("/agents/log")
def agents_log(agent: str | None = None, donation_id: int | None = None,
               limit: int = Query(50, ge=1, le=200),
               user: dict = Depends(require_role("admin")), db: Session = Depends(get_db)):
    return [dict(r) for r in db.execute(text("""
        SELECT action_id, agent, action, donation_id, match_id, delivery_id, used_llm, detail, created_at
          FROM agent_actions
         WHERE (CAST(:a AS TEXT) IS NULL OR agent = :a)
           AND (CAST(:d AS BIGINT) IS NULL OR donation_id = :d)
         ORDER BY action_id DESC LIMIT :l"""),
        {"a": agent, "d": donation_id, "l": limit}).mappings().all()]


@router.get("/donations/{donation_id}/agent-trace")
def agent_trace(donation_id: int, user: dict = Depends(get_current_user),
                db: Session = Depends(get_db)):
    """What the AI did for this donation. Visible to the donor who owns it, and admins."""
    owner = db.execute(text("SELECT donor_id FROM donations WHERE donation_id = :d"),
                       {"d": donation_id}).first()
    if not owner:
        raise HTTPException(404, "Donation not found")
    if user["role"] == "donor":
        if owner[0] != get_profile_id(db, user["user_id"], "donor"):
            raise HTTPException(403, "Not your donation")
    elif user["role"] != "admin":
        raise HTTPException(403, "Forbidden")
    return [dict(r) for r in db.execute(text("""
        SELECT agent, action, used_llm, detail, created_at FROM agent_actions
         WHERE donation_id = :d AND agent <> 'notification' ORDER BY action_id"""),
        {"d": donation_id}).mappings().all()]


@router.post("/donations/{donation_id}/matches/regenerate")
def regenerate_matches(donation_id: int, user: dict = Depends(require_role("donor", "admin")),
                       db: Session = Depends(get_db)):
    """Re-run the matching agent for a donation (documented in the backend README)."""
    row = db.execute(text("SELECT donor_id FROM donations WHERE donation_id = :d"),
                     {"d": donation_id}).first()
    if not row:
        raise HTTPException(404, "Donation not found")
    if user["role"] == "donor" and row[0] != get_profile_id(db, user["user_id"], "donor"):
        raise HTTPException(403, "Not your donation")
    n = matching_agent.run_for_donation(db, donation_id, "manual_regenerate", limit=10)
    matching_agent.explain(db, donation_id)
    db.commit()
    return {"new_matches": n}
