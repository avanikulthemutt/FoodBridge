from contextlib import contextmanager
from psycopg_pool import ConnectionPool
from .config import settings

pool = ConnectionPool(conninfo=settings.database_url, min_size=1, max_size=10, open=False)

def open_pool():
    pool.open(wait=True)

def close_pool():
    pool.close()

@contextmanager
def get_connection():
    with pool.connection() as conn:
        yield conn
