"""Run history persistence — SQLite at ~/.apex/runs.db"""
import sqlite3
import json
import time
from pathlib import Path

DB_PATH = Path.home() / ".apex" / "runs.db"

DDL_RUNS = """
CREATE TABLE IF NOT EXISTS runs (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    task         TEXT    NOT NULL,
    plan_json    TEXT,
    exit_code    INTEGER,
    token_count  INTEGER,
    wall_seconds REAL,
    timestamp    TEXT    NOT NULL DEFAULT (datetime('now','utc'))
);
"""

DDL_EVENTS = """
CREATE TABLE IF NOT EXISTS events (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    run_id      INTEGER NOT NULL REFERENCES runs(id),
    step        INTEGER NOT NULL,
    tool        TEXT    NOT NULL,
    args_json   TEXT,
    result_json TEXT,
    timestamp   TEXT    NOT NULL DEFAULT (datetime('now','utc'))
);
"""

def _conn() -> sqlite3.Connection:
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    con = sqlite3.connect(DB_PATH)
    con.execute(DDL_RUNS)
    con.execute(DDL_EVENTS)
    con.commit()
    return con

def record_run(task: str, plan: list | None, exit_code: int,
               token_count: int, wall_seconds: float) -> int:
    plan_json = json.dumps(plan) if plan is not None else None
    con = _conn()
    cur = con.execute(
        "INSERT INTO runs (task, plan_json, exit_code, token_count, wall_seconds) "
        "VALUES (?, ?, ?, ?, ?)",
        (task, plan_json, exit_code, token_count, wall_seconds),
    )
    con.commit()
    row_id = cur.lastrowid
    con.close()
    return row_id

def list_runs(n: int = 20) -> list[dict]:
    con = _conn()
    rows = con.execute(
        "SELECT id, task, exit_code, token_count, wall_seconds, timestamp "
        "FROM runs ORDER BY id DESC LIMIT ?", (n,)
    ).fetchall()
    con.close()
    return [
        dict(id=r[0], task=r[1], exit_code=r[2],
             token_count=r[3], wall_seconds=r[4], timestamp=r[5])
        for r in rows
    ]

def record_event(run_id: int, step: int, tool: str,
                 args: dict | None, result: dict | None) -> None:
    args_json   = json.dumps(args)   if args   is not None else None
    result_json = json.dumps(result) if result is not None else None
    con = _conn()
    con.execute(
        "INSERT INTO events (run_id, step, tool, args_json, result_json) "
        "VALUES (?, ?, ?, ?, ?)",
        (run_id, step, tool, args_json, result_json),
    )
    con.commit()
    con.close()

def aggregate_stats() -> dict:
    con = _conn()
    row = con.execute("""
        SELECT
            COUNT(*)                                        AS total,
            SUM(CASE WHEN exit_code = 0 THEN 1 ELSE 0 END) AS passed,
            AVG(token_count)                                AS avg_tokens,
            AVG(wall_seconds)                               AS avg_wall
        FROM runs
    """).fetchone()
    con.close()
    total, passed, avg_tokens, avg_wall = row
    total = total or 0
    passed = passed or 0
    return {
        "total": total,
        "passed": passed,
        "pass_rate": round(passed / total, 4) if total else 0.0,
        "avg_tokens": round(avg_tokens, 1) if avg_tokens else 0.0,
        "avg_wall_seconds": round(avg_wall, 3) if avg_wall else 0.0,
    }
