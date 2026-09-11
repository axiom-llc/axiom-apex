"""Persist run history and tool events in SQLite."""
import hashlib
import json
import os
import sqlite3
from contextlib import contextmanager
from pathlib import Path
from typing import Iterator

DB_PATH = Path(os.environ.get("APEX_HISTORY_DB_PATH", "~/.apex/runs.db")).expanduser()

_DDL_RUNS = """
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

_DDL_EVENTS = """
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

_DDL_LEDGER_RUNS = """
CREATE TABLE IF NOT EXISTS ledger_runs (
    run_id INTEGER PRIMARY KEY REFERENCES runs(id),
    plan_digest TEXT NOT NULL,
    step_count INTEGER NOT NULL
);
"""

_DDL_EFFECTS = """
CREATE TABLE IF NOT EXISTS effects (
    run_id INTEGER NOT NULL REFERENCES ledger_runs(run_id),
    step INTEGER NOT NULL,
    state TEXT NOT NULL CHECK(state IN
        ('INTENT_RECORDED', 'DISPATCHING', 'SUCCEEDED', 'FAILED_UNKNOWN')),
    result_json TEXT,
    PRIMARY KEY (run_id, step)
);
"""


class RecoveryBlocked(ValueError):
    """Durable evidence does not permit executing this run."""


def plan_digest(plan: dict) -> str:
    encoded = json.dumps(plan, sort_keys=True, ensure_ascii=False,
                         separators=(",", ":"), allow_nan=False)
    return hashlib.sha256(encoded.encode("utf-8")).hexdigest()


def _json(value) -> str | None:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":")) if value is not None else None


@contextmanager
def _conn() -> Iterator[sqlite3.Connection]:
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(DB_PATH, timeout=5.0)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys=ON")
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA synchronous=FULL")
    conn.execute("PRAGMA busy_timeout=5000")
    conn.execute(_DDL_RUNS)
    conn.execute(_DDL_EVENTS)
    conn.execute(_DDL_LEDGER_RUNS)
    conn.execute(_DDL_EFFECTS)
    try:
        yield conn
        conn.commit()
    finally:
        conn.close()


def begin_run(task: str, plan: dict, token_count: int) -> int:
    """Commit the complete accepted plan and all undispatched intents together."""
    digest = plan_digest(plan)
    with _conn() as conn:
        cursor = conn.execute(
            "INSERT INTO runs (task, plan_json, token_count) VALUES (?, ?, ?)",
            (task, _json(plan), token_count),
        )
        run_id = int(cursor.lastrowid)
        conn.execute("INSERT INTO ledger_runs VALUES (?, ?, ?)",
                     (run_id, digest, len(plan["steps"])))
        conn.executemany(
            "INSERT INTO effects (run_id, step, state) VALUES (?, ?, 'INTENT_RECORDED')",
            [(run_id, index) for index, step in enumerate(plan["steps"])
             if step["type"] == "tool"],
        )
    return run_id


def bound_effects(run_id: int, plan: dict) -> list[dict]:
    """Verify the complete binding before deciding any recovery step."""
    with _conn() as conn:
        row = conn.execute(
            "SELECT plan_json, plan_digest, step_count FROM runs "
            "JOIN ledger_runs ON runs.id=ledger_runs.run_id WHERE runs.id=?",
            (run_id,),
        ).fetchone()
        if row is None:
            raise RecoveryBlocked(f"run {run_id} has no durable effect ledger; live recovery blocked")
        if (plan_digest(plan) != row["plan_digest"]
                or plan_digest(json.loads(row["plan_json"])) != row["plan_digest"]
                or len(plan["steps"]) != row["step_count"]):
            raise RecoveryBlocked(f"run {run_id}: approved plan binding mismatch")
        rows = conn.execute("SELECT * FROM effects WHERE run_id=? ORDER BY step",
                            (run_id,)).fetchall()
        expected = [i for i, step in enumerate(plan["steps"]) if step["type"] == "tool"]
        if [row["step"] for row in rows] != expected:
            raise RecoveryBlocked(f"run {run_id}: incomplete effect ledger")
    return [dict(row) for row in rows]


def dispatch_effect(run_id: int, step: int) -> None:
    """Commit the ambiguous boundary before entering tool code."""
    with _conn() as conn:
        cursor = conn.execute(
            "UPDATE effects SET state='DISPATCHING' "
            "WHERE run_id=? AND step=? AND state='INTENT_RECORDED'", (run_id, step),
        )
        if cursor.rowcount != 1:
            raise RecoveryBlocked(f"run {run_id} step {step}: dispatch is not permitted")


def observe_effect(run_id: int, event: dict, *, succeeded: bool, retrying: bool = False) -> None:
    """Commit observed output; errors never establish that no effect occurred.

    During an explicitly retry-safe in-process retry, retain DISPATCHING and
    save the last observed error. A restart still blocks that ambiguous step.
    """
    state = "DISPATCHING" if retrying else ("SUCCEEDED" if succeeded else "FAILED_UNKNOWN")
    with _conn() as conn:
        cursor = conn.execute(
            "UPDATE effects SET state=?, result_json=? "
            "WHERE run_id=? AND step=? AND state='DISPATCHING'",
            (state, _json(event["result"]), run_id, event["step"]),
        )
        if cursor.rowcount != 1:
            raise RecoveryBlocked(f"run {run_id} step {event['step']}: outcome is not permitted")
        if not retrying:
            conn.execute(
                "INSERT INTO events (run_id, step, tool, args_json, result_json) VALUES (?, ?, ?, ?, ?)",
                (run_id, event["step"], event["tool"], _json(event["args"]), _json(event["result"])),
            )


def finish_run(run_id: int, exit_code: int, wall_seconds: float) -> None:
    """Update completion metadata without replacing the accepted plan/events."""
    with _conn() as conn:
        conn.execute("UPDATE runs SET exit_code=?, wall_seconds=? WHERE id=?",
                     (exit_code, wall_seconds, run_id))


def record_run(
    task: str,
    plan: dict | list | None,
    exit_code: int,
    token_count: int,
    wall_seconds: float,
    events: list[dict] | None = None,
) -> int:
    """Insert one run and all supplied events atomically; return the run id."""
    with _conn() as conn:
        cursor = conn.execute(
            "INSERT INTO runs (task, plan_json, exit_code, token_count, wall_seconds) "
            "VALUES (?, ?, ?, ?, ?)",
            (task, _json(plan), exit_code, token_count, wall_seconds),
        )
        run_id = int(cursor.lastrowid)
        for event in events or []:
            conn.execute(
                "INSERT INTO events (run_id, step, tool, args_json, result_json) "
                "VALUES (?, ?, ?, ?, ?)",
                (
                    run_id,
                    event["step"],
                    event["tool"],
                    _json(event.get("args")),
                    _json(event.get("result")),
                ),
            )
    return run_id


def list_runs(n: int = 20) -> list[dict]:
    limit = max(0, min(int(n), 1000))
    with _conn() as conn:
        rows = conn.execute(
            "SELECT id, task, exit_code, token_count, wall_seconds, timestamp "
            "FROM runs ORDER BY id DESC LIMIT ?",
            (limit,),
        ).fetchall()
    return [dict(row) for row in rows]


def load_events(run_id: int) -> list[dict]:
    with _conn() as conn:
        rows = conn.execute(
            "SELECT step, tool, args_json, result_json, timestamp FROM events "
            "WHERE run_id = ? ORDER BY step, id",
            (run_id,),
        ).fetchall()
    return [
        {
            "step": row["step"],
            "tool": row["tool"],
            "args": json.loads(row["args_json"]) if row["args_json"] else {},
            "result": json.loads(row["result_json"]) if row["result_json"] else {},
            "timestamp": row["timestamp"],
        }
        for row in rows
    ]


def load_run(run_id: int, *, include_events: bool = False) -> dict | None:
    with _conn() as conn:
        row = conn.execute("SELECT * FROM runs WHERE id = ?", (run_id,)).fetchone()
    if row is None:
        return None
    result = dict(row)
    result["plan"] = json.loads(result.pop("plan_json")) if result["plan_json"] else None
    if include_events:
        result["events"] = load_events(run_id)
    return result


def load_run_detail(run_id: int) -> dict | None:
    """Return the established HTTP run-detail shape with decoded plan_json."""
    with _conn() as conn:
        row = conn.execute("SELECT * FROM runs WHERE id = ?", (run_id,)).fetchone()
        if row is None:
            return None
        result = dict(row)
        result["plan_json"] = (
            json.loads(result["plan_json"]) if result["plan_json"] else None
        )
        ledger = conn.execute("SELECT plan_digest, step_count FROM ledger_runs WHERE run_id=?",
                              (run_id,)).fetchone()
        result["ledger"] = dict(ledger) if ledger is not None else None
        result["effects"] = [dict(effect) for effect in conn.execute(
            "SELECT step, state, result_json FROM effects WHERE run_id=? ORDER BY step",
            (run_id,),
        ).fetchall()]
        result["events"] = [
            dict(event)
            for event in conn.execute(
                "SELECT * FROM events WHERE run_id = ? ORDER BY step, id",
                (run_id,),
            ).fetchall()
        ]
    return result


def aggregate_stats() -> dict:
    with _conn() as conn:
        row = conn.execute(
            """
            SELECT
                COUNT(*) AS total,
                SUM(CASE WHEN exit_code = 0 THEN 1 ELSE 0 END) AS passed,
                AVG(token_count) AS avg_tokens,
                AVG(wall_seconds) AS avg_wall
            FROM runs
            """
        ).fetchone()
    total = int(row["total"] or 0)
    passed = int(row["passed"] or 0)
    return {
        "total": total,
        "passed": passed,
        "pass_rate": round(passed / total, 4) if total else 0.0,
        "avg_tokens": round(float(row["avg_tokens"] or 0.0), 1),
        "avg_wall_seconds": round(float(row["avg_wall"] or 0.0), 3),
    }
