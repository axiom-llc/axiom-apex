"""SQLite-based memory implementation"""
import sqlite3
import json
from contextlib import contextmanager
from pathlib import Path
from time import time
from core.types import Tool

DB_PATH = Path.home() / '.apex' / 'memory.db'


def _init_db():
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    with _db() as conn:
        conn.execute('''
            CREATE TABLE IF NOT EXISTS entries (
                id INTEGER PRIMARY KEY,
                data TEXT,
                timestamp REAL
            )
        ''')


@contextmanager
def _db():
    conn = sqlite3.connect(DB_PATH)
    try:
        yield conn
        conn.commit()
    finally:
        conn.close()


_init_db()


def memory_read_effect(args: dict) -> dict:
    with _db() as conn:
        cursor = conn.execute('SELECT data, timestamp FROM entries ORDER BY timestamp DESC')
        entries = [{'data': json.loads(row[0]), 'timestamp': row[1]} for row in cursor.fetchall()]
    return {'entries': entries}


def memory_write_effect(args: dict) -> dict:
    with _db() as conn:
        conn.execute('INSERT INTO entries (data, timestamp) VALUES (?, ?)',
                     (json.dumps(args['entry']), time()))
    return {'success': True}


MEMORY_READ = Tool(
    name='memory_read',
    input_spec={},
    output_spec={'entries': list},
    effect=memory_read_effect
)

MEMORY_WRITE = Tool(
    name='memory_write',
    input_spec={'entry': dict},
    output_spec={'success': bool},
    effect=memory_write_effect
)
