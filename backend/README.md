# FoodBridge API (Phase 1 foundation)

FastAPI service wired to the existing PostgreSQL schema. The original frontend and database scripts are preserved in this project bundle.

## Requirements
- Python 3.11+
- PostgreSQL 14+

## Setup

```bash
# 1. Create the database and apply the supplied SQL (from project root)
psql -U postgres -c "CREATE DATABASE foodbridge;"
psql -U postgres -d foodbridge -f database/00_run_all_in_foodbridge.sql

# 2. Configure backend
cd backend
python -m venv .venv
# Windows: .venv\\Scripts\\activate
# macOS/Linux: source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
# Edit DATABASE_URL and JWT_SECRET in .env

# 3. Run API
uvicorn app.main:app --reload
```

API docs: http://127.0.0.1:8000/docs
Health: http://127.0.0.1:8000/health

## Implemented in this foundation
- PostgreSQL connection pool
- Health check
- Provider (`donor` in the supplied schema) and NGO registration
- Login with bcrypt password hashing and signed JWT access token
- Live impact summary backed by `v_impact_summary`
- CORS configuration for the frontend dev server

## Important schema mapping
The project description calls the food-provider role `provider`; the supplied SQL schema calls it `donor`. This API preserves the database's existing `donor` role and exposes that role to the client. The description's provider terminology can be used in the UI. The supplied schema currently has no admin role, no historical meal/preparation records, and no ML prediction/evaluation tables; these will be added in later, versioned migrations rather than silently overloading donation tables.

## Security and deployment notes
- Replace `JWT_SECRET` with a long random secret before use.
- Do not commit `.env` or production credentials.
- NGO accounts are created with `verification_status='pending'` by the supplied schema; acceptance and restricted actions must remain blocked until admin verification is implemented.
- This is the first integration foundation, not the complete feature set yet.
