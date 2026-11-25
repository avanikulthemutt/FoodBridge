# Add agents to your FoodBridge backend
1. Run db/06_agent_tables.sql on the foodbridge database.
2. Copy app/agents/ and app/routers/agents.py into your backend's app/ folder (tests/ and AGENTS.md go in the backend root).
3. pip install anthropic   (and add `anthropic>=0.40` to requirements.txt)
4. Add these settings to app/config.py (Settings class):
   AGENTS_ENABLED: bool = True
   AGENT_CYCLE_SECONDS: int = 60
   ANTHROPIC_API_KEY: str = ""
   AGENT_LLM_ENABLED: bool = True
   AGENT_MODEL: str = "claude-haiku-5-5"
   MATCH_RESPONSE_TIMEOUT_MINS: int = 15
   MATCH_REMINDER_MINS: int = 8
   PICKUP_NOSHOW_MINS: int = 20
   NO_VOLUNTEER_ALERT_MINS: int = 10
   ENFORCE_SHELF_LIFE: bool = True
5. In app/main.py: import `agents` router + `orchestrator`, call app.include_router(agents.router),
   and run orchestrator.run_cycle in the startup loop (see the full backend zip for the exact code).
6. In routers/ngos.py and volunteers.py use pickup_agent.assign(db, delivery_id) instead of assign_nearest_volunteer.
Easiest: use foodbridge_backend_with_agents.zip, which already has all of this wired in.
