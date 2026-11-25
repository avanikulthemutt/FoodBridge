"""Integration tests run against a throwaway Postgres database built from the foodbridge_db SQL files.
  export PG_ADMIN_URL=postgresql+psycopg2://postgres:postgres@localhost:5432/postgres
  export FOODBRIDGE_SQL_DIR=../foodbridge_db      # folder holding 00_run_all_in_foodbridge.sql + 06_agent_tables.sql
  pytest -q
"""
import os
import pathlib

import psycopg2
import pytest
from sqlalchemy.engine import make_url

ADMIN = os.environ.get("PG_ADMIN_URL", "postgresql+psycopg2://postgres:postgres@localhost:5432/postgres")
SQL_DIR = pathlib.Path(os.environ.get("FOODBRIDGE_SQL_DIR", "../foodbridge_db"))
TEST_DB = "foodbridge_agents_test"
u = make_url(ADMIN)
os.environ["DATABASE_URL"] = u.set(database=TEST_DB).render_as_string(hide_password=False)
os.environ["ANTHROPIC_API_KEY"] = ""  # tests exercise the rule-based path unless they stub the LLM


def _connect(db):
    return psycopg2.connect(host=u.host, port=u.port, user=u.username, password=u.password, dbname=db)


@pytest.fixture()
def fresh_db():
    """Rebuild the database before every test so tests never affect each other."""
    c = _connect("postgres"); c.autocommit = True
    cur = c.cursor()
    cur.execute(f"DROP DATABASE IF EXISTS {TEST_DB} WITH (FORCE)")
    cur.execute(f"CREATE DATABASE {TEST_DB}")
    c.close()
    t = _connect(TEST_DB); t.autocommit = True
    cur = t.cursor()
    for f in ("00_run_all_in_foodbridge.sql", "06_agent_tables.sql"):
        cur.execute((SQL_DIR / f).read_text())
    t.close()
    from app.database import engine
    engine.dispose()
    from app.database import SessionLocal
    db = SessionLocal()
    yield db
    db.close()
    engine.dispose()
