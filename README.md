# FoodBridge — Predict. Prevent. Rescue.

FoodBridge is an AI-assisted food-demand forecasting, food-waste prevention, and verified-surplus donation application. This repository includes the complete runnable prototype, its source, automated tests, the supplied original frontend/database assets, and the earlier PostgreSQL API foundation for reference.

## What is runnable in this ZIP

The integrated application is **FastAPI + SQLite + a responsive HTML/CSS/JavaScript frontend**, with Pandas, NumPy, Scikit-learn and Joblib for forecasting. This follows the original specification's initial prototype stack (Python, Streamlit/SQLite was proposed there; this build uses FastAPI to serve the supplied web-app direction while retaining SQLite for a one-command local setup). The integrated frontend is served by the same FastAPI process at `/`; API documentation is at `/docs`.

The original `frontend/`, `backend/`, and `database/` directories are retained unchanged as supplied reference material. In particular, the original PostgreSQL SQL scripts and PostgreSQL foundation under `backend/` are **not** the database used by this integrated runnable prototype. The active app uses SQLite so that it can be installed and tested locally without a separately provisioned PostgreSQL server. Do not assume the reference PostgreSQL schema is connected to this app.

## Implemented modules

- Provider and NGO registration, sign-in, signed 24-hour bearer sessions, PBKDF2 password hashing, role checks, account suspension, and profile editing.
- Admin account seeded locally (no public admin self-registration); NGO verification/rejection and platform moderation.
- Provider historical food records: create, edit, delete, date/meal/category filtering, CSV import/export, duplicate handling and quantity validation.
- Demand forecasting: Scikit-learn Random Forest Regressor, recent-average baseline comparison, chronological train/test split, MAE/RMSE/R², Joblib persistence, feature-importance explanation, configurable event/holiday inputs, and an explicitly labelled fallback when matching history is insufficient.
- Predictive alerts and model evaluation history. Predicted surplus never creates a donation.
- What-if simulator: formula-based surplus, waste %, coverage, recommendation and potential-surplus-reduction calculations; updates as inputs change.
- Actual surplus donation listings are linked to a provider's recorded preparation/consumption entry. Quantity cannot exceed unallocated recorded surplus. Preparation, pickup and safe-consumption times, food type, storage, location and contact are validated.
- Verified NGO browsing and filtering; configurable weighted matching with reasons; acceptance, rejection, pickup scheduling, pickup/delivery/completion confirmation; cancellation and expiry; atomic single-NGO acceptance; timestamped status history.
- Food-safety guardrails: human provider confirmation, unknown-storage manual-review flag, admin review/removal, deadline enforcement, and explicit non-certification language.
- Provider, NGO and platform analytics; prediction-vs-actual comparisons; prepared/consumed/surplus trends; notification inbox; pickup reminders when the app checks active listings; user reports.
- Admin dashboard for NGO verification, account suspension, donation moderation, prediction activity, reports and configurable risk/matching weights.

## Requirements

- Python 3.11 or newer
- pip

## Quick start (Windows PowerShell)

```powershell
cd FoodBridgeComplete
py -m venv .venv
.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
pip install -r requirements.txt
$env:FOODBRIDGE_SECRET = "replace-this-with-a-long-random-secret"
python -m foodbridge_app.seed
uvicorn foodbridge_app.main:app --host 127.0.0.1 --port 8000
```

Open <http://127.0.0.1:8000>. API docs: <http://127.0.0.1:8000/docs>.

## Quick start (macOS / Linux)

```bash
cd FoodBridgeComplete
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
pip install -r requirements.txt
export FOODBRIDGE_SECRET="replace-this-with-a-long-random-secret"
python -m foodbridge_app.seed
uvicorn foodbridge_app.main:app --host 127.0.0.1 --port 8000
```

The database is created as `foodbridge.db` in the project root by default. Set `FOODBRIDGE_DB` to an absolute path to put it elsewhere. The model file is saved under `models/` per provider.

## Local demo accounts

Run `python -m foodbridge_app.seed` once on a fresh database. It creates illustrative synthetic records and these accounts:

| Role | Email | Password |
|---|---|---|
| Admin | `admin@foodbridge.example.com` | `Admin@12345` |
| Provider | `provider@foodbridge.example.com` | `Provider@12345` |
| Verified NGO | `ngo@foodbridge.example.com` | `Ngo@1234567` |

The seed script does nothing if the database already contains users. The synthetic food records are labelled in their notes and must not be treated as real observations. Change demo passwords and `FOODBRIDGE_SECRET` before using any non-local environment.

## Test the application

```bash
python -m pytest -q
```

The automated suite exercises registration and login, role restrictions and provider data isolation, NGO verification, historical record CRUD/validation, CSV import/export and duplicate handling, Random Forest training/persistence/evaluation, predictions, simulator formulas, actual-surplus-linked donation creation, the full donation status lifecycle, safety review, impact accounting and the insufficient-data fallback. It uses a temporary SQLite database and does not modify the demo database. See `TEST_RESULTS.md` for the verification report and test boundaries.

A basic live-server check after startup:

```bash
curl http://127.0.0.1:8000/health
```

Expected response: `{"status":"ok","database":"connected","app":"FoodBridge"}`. See [TEST_RESULTS.md](TEST_RESULTS.md) for the recorded test and smoke-check results, including what could not be tested in this environment.

## Important operating rules and limitations

1. A forecast is an estimate, not a guarantee. The app reports a recent-average fallback until there is enough matching history; the fallback is never labelled as a trained Random Forest.
2. The model uses historical meal demand, weekday, meal type/category, recent lags, previous preparation/surplus and event/holiday flags. Optional weather is retained as record metadata but is not currently a model feature.
3. The model evaluation uses a chronological holdout. The recent-average baseline is reported alongside Random Forest performance. Evaluation metrics are not a guarantee of future accuracy.
4. A donation must be tied to an actual food record and cannot exceed that record's remaining unallocated surplus. A prediction alone cannot be donated.
5. Confirmed donated quantity counts only donations marked **Completed**. Remaining actual waste is recorded surplus less completed donations linked to those records. Potential prevention is a separate estimate and uses only the latest prediction for each date/meal/category to avoid repeated-prediction double counting.
6. FoodBridge does not certify food safety. Providers and receiving NGOs remain responsible for human checks under applicable rules. Unknown storage is held for admin review; deadlines are enforced.
7. NGO matching uses entered city/location text and profile suitability; there is no geocoding, live GPS, routing or guaranteed distance calculation.
8. Notifications are in-app. Pickup reminder notifications are generated when an authenticated user checks listings; there is no background scheduler, email/SMS/WhatsApp gateway or push service in this local prototype.
9. The local SQLite prototype is not hardened for public production hosting. Before deployment, replace the secret, configure HTTPS, use a managed database, review privacy/retention, add rate limits/backups, and run security/load testing.

## Project structure

```text
FoodBridgeComplete/
  foodbridge_app/          # Integrated runnable FastAPI app, database, ML, UI
    static/                # Served frontend
  tests/                   # Automated tests
  models/                  # Generated per-provider Joblib models (created at runtime)
  frontend/                # Original supplied frontend reference
  backend/                 # Original supplied PostgreSQL API foundation reference
  database/                # Original supplied PostgreSQL SQL scripts
  requirements.txt
  .env.example
```

## API groups

- `/api/auth/*`, `/api/me`, `/api/profile`
- `/api/records/*`, `/api/ml/*`, `/api/predictions`, `/api/simulator`
- `/api/donations/*`, `/api/matches/{donation_id}`
- `/api/notifications`, `/api/alerts`, `/api/reports`
- `/api/analytics`, `/api/analytics/trends`
- `/api/admin/*`

See `/docs` for the complete interactive API schema.
