-- ============================================================
-- FoodBridge: Step 6 - AI agent audit log
-- Run AFTER 02-04. Every decision an agent makes is stored here,
-- so the admin dashboard can show "what the AI did and why".
-- dedupe_key makes agent actions idempotent (e.g. one reminder per match).
-- ============================================================
CREATE TABLE IF NOT EXISTS agent_actions (
    action_id    BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    agent        VARCHAR(20) NOT NULL
                 CHECK (agent IN ('matching', 'freshness', 'notification', 'pickup', 'orchestrator')),
    action       VARCHAR(60) NOT NULL,
    donation_id  BIGINT REFERENCES donations(donation_id)  ON DELETE CASCADE,
    match_id     BIGINT REFERENCES matches(match_id)       ON DELETE SET NULL,
    delivery_id  BIGINT REFERENCES deliveries(delivery_id) ON DELETE SET NULL,
    dedupe_key   VARCHAR(120) UNIQUE,
    used_llm     BOOLEAN NOT NULL DEFAULT FALSE,
    detail       JSONB   NOT NULL DEFAULT '{}'::jsonb,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_agent_actions_donation ON agent_actions (donation_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_agent_actions_agent    ON agent_actions (agent, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_agent_actions_delivery ON agent_actions (delivery_id, action);
