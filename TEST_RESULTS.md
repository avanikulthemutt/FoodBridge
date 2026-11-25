# FoodBridge verification report

Build verification performed: 25 November 2026.

## Automated tests

Command:

```bash
python -m pytest -q
```

Result: **6 passed**.

Coverage run:

```bash
python -m pytest -q --cov=foodbridge_app --cov-report=term-missing
```

Result in the build environment: **79% total statement coverage** (database module 100%, API module 79%, ML module 89%, security module 91%). Coverage is a test signal, not proof of production readiness.

The tests exercise authentication and role boundaries, provider data isolation, historical record CRUD and validation, CSV import/export and duplicate handling, Random Forest training and persisted model path, chronological holdout metrics and baseline comparison, insufficient-history fallback, prediction output, simulator calculations, donation quantity and record-link safeguards, NGO verification, food-safety review, donation status transitions and pickup-window validation, impact accounting, and completed-donation tracking.

## Runtime smoke checks

A local Uvicorn process was started against a fresh temporary SQLite database. These checks passed:

- `GET /health` returned `status=ok` and `database=connected`.
- `GET /` served the integrated frontend.
- `GET /static/app.js` served the application JavaScript.
- `GET /openapi.json` generated the API schema (31 API paths).
- `node --check foodbridge_app/static/app.js` passed.
- `python -m compileall -q foodbridge_app tests` passed.

## Boundaries of this verification

- PostgreSQL is **not** the active database in this runnable local prototype. The active app uses SQLite. The supplied PostgreSQL scripts and earlier PostgreSQL foundation are included as reference assets but are not wired into the active app.
- A live PostgreSQL integration test was not possible because no PostgreSQL server/client was available in the build environment.
- A real-browser end-to-end run was not performed because a Chromium browser binary was unavailable. API integration tests, JavaScript syntax validation and HTTP serving smoke checks were performed instead.
- This is a local runnable prototype, not a hardened public production deployment. Review the README's security, notification, location and deployment limitations before external use.
