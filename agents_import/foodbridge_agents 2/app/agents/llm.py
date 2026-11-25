"""Optional Claude wrapper. If no ANTHROPIC_API_KEY is set (or the call fails),
every function returns None and the agents use their rule-based fallback.
So the platform never depends on the LLM being up."""
import json
import logging
import re
from typing import Optional

from ..config import settings

logger = logging.getLogger("foodbridge.agents.llm")
_client = None


def enabled() -> bool:
    return bool(settings.ANTHROPIC_API_KEY) and settings.AGENT_LLM_ENABLED


def _get_client():
    global _client
    if _client is None:
        import anthropic  # lazy: app still boots if the package is missing
        _client = anthropic.Anthropic(api_key=settings.ANTHROPIC_API_KEY,
                                      timeout=20.0, max_retries=1)
    return _client


def ask(system: str, user: str, max_tokens: int = 500) -> Optional[str]:
    if not enabled():
        return None
    try:
        msg = _get_client().messages.create(
            model=settings.AGENT_MODEL, max_tokens=max_tokens, system=system,
            messages=[{"role": "user", "content": user}],
        )
        return "".join(b.text for b in msg.content if getattr(b, "type", "") == "text").strip()
    except Exception as exc:
        logger.warning("LLM call failed, using fallback: %s", exc)
        return None


def ask_json(system: str, user: str, max_tokens: int = 500) -> Optional[dict]:
    raw = ask(system, user, max_tokens)
    if not raw:
        return None
    match = re.search(r"\{.*\}", raw, re.S)
    if not match:
        return None
    try:
        data = json.loads(match.group(0))
        return data if isinstance(data, dict) else None
    except json.JSONDecodeError:
        return None
