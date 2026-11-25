# FoodBridge AI Agents

Matches the "AI Agents" box in the architecture diagram: **matching, freshness, notifications, pickup**.

```
FastAPI request ──► DB functions (hard rules, OTPs, scoring)
                          ▲
 Orchestrator (every 60 s, one worker via advisory lock)
   1. Freshness     2. Matching     3. Pickup     4. Notification
                          │
                   agent_actions table  (audit log: what, why, LLM or rules)
```

| Agent | Watches | Decides / does |
|---|---|---|
| **Freshness** | donations not yet delivered | effective deadline = min(donor expiry, category shelf life, cold-chain break); raises urgency as time runs out (never lowers); expires unsafe food and cancels its pickup; optional Claude food-safety review (advisory only) |
| **Matching** | offers to NGOs | explains each NGO's rank + recommends one; if every NGO is silent for 15 min, expires the offers and widens to the next NGOs (max 3 rounds); retries donations nobody could take; tells donor/admin when stuck |
| **Pickup** | accepted donations | picks volunteer by ETA + vehicle fit; sends the donor the pickup OTP; releases no-shows (20 min) and reassigns to someone else; if nobody is free, alerts NGO (self-pickup if it has transport) and admins |
| **Notification** | everything | single outlet for all messages, one per `dedupe_key` (no spam); reminders to slow NGOs; pickup/delivery confirmations with impact numbers |

## Safety design
- SQL stays the gatekeeper. The LLM only explains/recommends among NGOs SQL already approved; a hallucinated id is ignored.
- Without `ANTHROPIC_API_KEY` everything runs on rule-based fallbacks. LLM failure never breaks a cycle.
- User-written text (titles, notes) is passed to the LLM as tagged data, and its output is validated before use.
- Each agent runs in its own transaction; one crashing doesn't stop the others.

## Setup
```bash
psql -U postgres -d foodbridge -f ../foodbridge_db/06_agent_tables.sql
pip install -r requirements.txt
# .env: ANTHROPIC_API_KEY=...   (optional)
uvicorn app.main:app --reload
```

## Endpoints
| Endpoint | Who | What |
|---|---|---|
| `GET /api/agents/status` | admin | enabled?, LLM on?, last cycle, 24 h action counts |
| `POST /api/agents/run` | admin | run one cycle now (great for demos) |
| `GET /api/agents/log?agent=&donation_id=` | admin | audit trail |
| `GET /api/donations/{id}/agent-trace` | donor (owner) / admin | "what the AI did for my donation" |
| `POST /api/donations/{id}/matches/regenerate` | donor / admin | re-run matching (was in README, now exists) |

## Tuning (`.env`)
`AGENT_CYCLE_SECONDS`, `MATCH_RESPONSE_TIMEOUT_MINS`, `MATCH_REMINDER_MINS`, `PICKUP_NOSHOW_MINS`,
`NO_VOLUNTEER_ALERT_MINS`, `ENFORCE_SHELF_LIFE`, `AGENT_MODEL`.
Vehicle speeds/capacities live in `pickup_agent.VEHICLES`; they are assumptions, tune them.

## Tests
```bash
export PG_ADMIN_URL=postgresql+psycopg2://postgres:postgres@localhost:5432/postgres
export FOODBRIDGE_SQL_DIR=../foodbridge_db
pytest -q        # 8 integration tests on a throwaway DB
```
