"""Shared helpers for all agents: audit logging with idempotency."""
import json
from datetime import datetime, timezone

from sqlalchemy import text
from sqlalchemy.orm import Session


def now_utc() -> datetime:
    return datetime.now(timezone.utc)


def log_action(db: Session, agent: str, action: str, *, donation_id=None, match_id=None,
               delivery_id=None, dedupe_key: str | None = None, used_llm: bool = False,
               detail: dict | None = None) -> bool:
    """Write one row to agent_actions. Returns False if dedupe_key already exists
    (meaning this exact action was already done) - callers use that to stay idempotent."""
    row = db.execute(text("""
        INSERT INTO agent_actions (agent, action, donation_id, match_id, delivery_id,
                                   dedupe_key, used_llm, detail)
        VALUES (:agent, :action, :did, :mid, :dlid, :dk, :llm, CAST(:detail AS jsonb))
        ON CONFLICT (dedupe_key) DO NOTHING
        RETURNING action_id"""),
        {"agent": agent, "action": action, "did": donation_id, "mid": match_id,
         "dlid": delivery_id, "dk": dedupe_key, "llm": used_llm,
         "detail": json.dumps(detail or {}, default=str)}).first()
    return row is not None


def already_done(db: Session, dedupe_key: str) -> bool:
    return db.execute(text("SELECT 1 FROM agent_actions WHERE dedupe_key = :k"),
                      {"k": dedupe_key}).first() is not None
