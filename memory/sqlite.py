"""SQLite-based memory implementation"""
import sqlite3
import json
from pathlib import Path
from time import time
from core.types import Tool

DB_PATH = Path.home() / '.apex' / 'memory.db'

def init_db():
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.execute('''
        CREATE TABLE IF NOT EXISTS entries (
            id INTEGER PRIMARY KEY,
            data TEXT,
            timestamp REAL
        )
    ''')
    conn.commit()
    conn.close()

def memory_read_effect(args: dict) -> dict:
    init_db()
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.execute('SELECT data, timestamp FROM entries ORDER BY timestamp DESC')
    entries = [{'data': json.loads(row[0]), 'timestamp': row[1]} for row in cursor.fetchall()]
    conn.close()
    return {'entries': entries}

def memory_write_effect(args: dict) -> dict:
    init_db()
    conn = sqlite3.connect(DB_PATH)
    conn.execute('INSERT INTO entries (data, timestamp) VALUES (?, ?)',
                 (json.dumps(args['entry']), time()))
    conn.commit()
    conn.close()
    return {'success': True}

MEMORY_READ = Tool(
    name='memory_read',
    input_spec={'query': dict},
    output_spec={'entries': list},
    effect=memory_read_effect
)

MEMORY_WRITE = Tool(
    name='memory_write',
    input_spec={'entry': dict},
    output_spec={'success': bool},
    effect=memory_write_effect
)
