"""SQLite persistence for the runnable FoodBridge prototype."""
import os, sqlite3
from pathlib import Path
from contextlib import contextmanager

DB_PATH = os.getenv('FOODBRIDGE_DB', str(Path(__file__).resolve().parent.parent / 'foodbridge.db'))

SCHEMA = '''
PRAGMA foreign_keys=ON;
CREATE TABLE IF NOT EXISTS users (
 id INTEGER PRIMARY KEY, name TEXT NOT NULL, email TEXT NOT NULL UNIQUE COLLATE NOCASE,
 password_hash TEXT NOT NULL, role TEXT NOT NULL CHECK(role IN ('provider','ngo','admin')),
 phone TEXT, status TEXT NOT NULL DEFAULT 'active', created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS providers (
 user_id INTEGER PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
 organization_name TEXT NOT NULL, organization_type TEXT NOT NULL, address TEXT NOT NULL, city TEXT NOT NULL,
 food_categories TEXT NOT NULL DEFAULT '', contact_person TEXT NOT NULL DEFAULT ''
);
CREATE TABLE IF NOT EXISTS ngos (
 user_id INTEGER PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
 ngo_name TEXT NOT NULL, address TEXT NOT NULL, city TEXT NOT NULL, service_area TEXT NOT NULL DEFAULT '', description TEXT NOT NULL DEFAULT '',
 people_served INTEGER NOT NULL DEFAULT 0, collection_capacity INTEGER NOT NULL DEFAULT 0,
 food_requirements TEXT NOT NULL DEFAULT '', preferred_categories TEXT NOT NULL DEFAULT '',
 verification_status TEXT NOT NULL DEFAULT 'pending', available_for_pickup INTEGER NOT NULL DEFAULT 1
);
CREATE TABLE IF NOT EXISTS food_records (
 id INTEGER PRIMARY KEY, provider_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 record_date TEXT NOT NULL, meal_type TEXT NOT NULL, food_category TEXT NOT NULL,
 prepared INTEGER NOT NULL CHECK(prepared>0), consumed INTEGER NOT NULL CHECK(consumed>=0 AND consumed<=prepared),
 surplus INTEGER NOT NULL CHECK(surplus>=0), event_indicator INTEGER NOT NULL DEFAULT 0,
 holiday_indicator INTEGER NOT NULL DEFAULT 0, weather TEXT, notes TEXT,
 created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP, UNIQUE(provider_id,record_date,meal_type,food_category)
);
CREATE TABLE IF NOT EXISTS predictions (
 id INTEGER PRIMARY KEY, provider_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 prediction_date TEXT NOT NULL, meal_type TEXT NOT NULL, food_category TEXT NOT NULL,
 planned_preparation INTEGER NOT NULL, predicted_demand REAL NOT NULL, estimated_surplus INTEGER NOT NULL,
 recommended_preparation INTEGER NOT NULL, waste_percentage REAL NOT NULL, risk_level TEXT NOT NULL,
 model_version TEXT NOT NULL, prediction_source TEXT NOT NULL, explanation TEXT NOT NULL,
 potential_prevention REAL NOT NULL DEFAULT 0, actual_consumed INTEGER,
 created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS donations (
 id INTEGER PRIMARY KEY, provider_id INTEGER NOT NULL REFERENCES users(id), ngo_id INTEGER REFERENCES users(id),
 food_record_id INTEGER NOT NULL REFERENCES food_records(id), food_name TEXT NOT NULL, food_category TEXT NOT NULL, quantity INTEGER NOT NULL CHECK(quantity>0), meal_type TEXT NOT NULL,
 food_type TEXT NOT NULL, preparation_time TEXT NOT NULL, pickup_start TEXT NOT NULL, pickup_deadline TEXT NOT NULL, scheduled_pickup_at TEXT,
 safe_consumption_deadline TEXT NOT NULL, storage_method TEXT NOT NULL, pickup_location TEXT NOT NULL,
 contact_information TEXT NOT NULL, notes TEXT, provider_verified INTEGER NOT NULL DEFAULT 0,
 safety_review_required INTEGER NOT NULL DEFAULT 0,
 status TEXT NOT NULL DEFAULT 'Available', created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS donation_history (
 id INTEGER PRIMARY KEY, donation_id INTEGER NOT NULL REFERENCES donations(id) ON DELETE CASCADE,
 updated_by INTEGER NOT NULL REFERENCES users(id), previous_status TEXT, new_status TEXT NOT NULL,
 remarks TEXT, updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS notifications (
 id INTEGER PRIMARY KEY, user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 title TEXT NOT NULL, message TEXT NOT NULL, notification_type TEXT NOT NULL,
 is_read INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS model_evaluations (
 id INTEGER PRIMARY KEY, provider_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 model_version TEXT NOT NULL, training_date TEXT NOT NULL, mae REAL, rmse REAL, r2 REAL,
 training_records INTEGER NOT NULL, testing_records INTEGER NOT NULL, model_path TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS user_reports (
 id INTEGER PRIMARY KEY, reporter_id INTEGER NOT NULL REFERENCES users(id), subject TEXT NOT NULL,
 details TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'open', created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS app_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL);
'''

@contextmanager
def connect():
    conn = sqlite3.connect(DB_PATH, timeout=20)
    conn.row_factory = sqlite3.Row
    conn.execute('PRAGMA foreign_keys=ON')
    conn.execute('PRAGMA journal_mode=WAL')
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback(); raise
    finally: conn.close()

def init_db():
    Path(DB_PATH).parent.mkdir(parents=True, exist_ok=True)
    with connect() as c:
        c.executescript(SCHEMA)
        cols={r['name'] for r in c.execute('PRAGMA table_info(donations)').fetchall()}
        if 'scheduled_pickup_at' not in cols: c.execute('ALTER TABLE donations ADD COLUMN scheduled_pickup_at TEXT')
        if 'food_record_id' not in cols: c.execute('ALTER TABLE donations ADD COLUMN food_record_id INTEGER REFERENCES food_records(id)')
        ngo_cols={r['name'] for r in c.execute('PRAGMA table_info(ngos)').fetchall()}
        if 'description' not in ngo_cols: c.execute("ALTER TABLE ngos ADD COLUMN description TEXT NOT NULL DEFAULT ''")
        if 'available_for_pickup' not in ngo_cols: c.execute('ALTER TABLE ngos ADD COLUMN available_for_pickup INTEGER NOT NULL DEFAULT 1')
        defaults = {'safety_buffer_percent':'3','low_risk_percent':'5','medium_risk_percent':'15',
                    'match_location_weight':'35','match_capacity_weight':'25','match_requirement_weight':'20',
                    'match_availability_weight':'10','match_preference_weight':'10'}
        c.executemany('INSERT OR IGNORE INTO app_settings(key,value) VALUES(?,?)', defaults.items())
