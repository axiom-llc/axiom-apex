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

_DDL_REGISTRY_BINDINGS = """
CREATE TABLE IF NOT EXISTS registry_bindings (
    run_id INTEGER PRIMARY KEY REFERENCES ledger_runs(run_id),
    contract_digest TEXT NOT NULL
);
"""

_DDL_AUTHORIZATIONS = """
CREATE TABLE IF NOT EXISTS authorizations (
    run_id INTEGER PRIMARY KEY REFERENCES ledger_runs(run_id),
    authorization_id TEXT NOT NULL,
    approved_plan_digest TEXT NOT NULL,
    policy_digest_or_ref TEXT NOT NULL,
    authority_ref TEXT NOT NULL,
    decision INTEGER NOT NULL CHECK(decision IN (0, 1))
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


def _type_ref(value: type) -> str:
    if not isinstance(value, type):
        raise TypeError("tool schema entries must be concrete types")
    return f"{value.__module__}.{value.__qualname__}"


def tool_registry_contract_digest(registry: dict) -> str:
    """Hash the planner-visible tool contract, not implementation code or provider state."""
    contracts = []
    for registry_key in sorted(registry):
        tool = registry[registry_key]
        contracts.append({
            "registry_key": registry_key,
            "name": tool.name,
            "input_spec": {
                key: _type_ref(value) for key, value in sorted(tool.input_spec.items())
            },
            "output_spec": {
                key: _type_ref(value) for key, value in sorted(tool.output_spec.items())
            },
            "required": sorted(tool.required_args),
            "retry_safe": bool(tool.retry_safe),
        })
    encoded = json.dumps(
        contracts, sort_keys=True, ensure_ascii=False,
        separators=(",", ":"), allow_nan=False,
    )
    return hashlib.sha256(encoded.encode("utf-8")).hexdigest()


def _json(value) -> str | None:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":")) if value is not None else None


def validate_authorization(authorization: dict, plan: dict) -> dict:
    """Validate and normalize one authorization binding for an exact plan."""
    if not isinstance(authorization, dict):
        raise RecoveryBlocked("authorization must be an object")

    fields = ("authorization_id", "approved_plan_digest", "policy_digest_or_ref", "authority_ref")
    normalized = {}
    for field in fields:
        value = authorization.get(field)
        if not isinstance(value, str) or not value.strip():
            raise RecoveryBlocked(f"authorization {field} must be a non-empty string")
        normalized[field] = value.strip()

    decision = authorization.get("decision")
    if decision is not True:
        raise RecoveryBlocked("authorization decision must be true")
    normalized["decision"] = True

    digest = plan_digest(plan)
    if normalized["approved_plan_digest"] != digest:
        raise RecoveryBlocked("authorization approved plan digest mismatch")
    return normalized


def _authorization_dict(row: sqlite3.Row) -> dict:
    return {
        "authorization_id": row["authorization_id"],
        "approved_plan_digest": row["approved_plan_digest"],
        "policy_digest_or_ref": row["policy_digest_or_ref"],
        "authority_ref": row["authority_ref"],
        "decision": bool(row["decision"]),
    }


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
    conn.execute(_DDL_REGISTRY_BINDINGS)
    conn.execute(_DDL_AUTHORIZATIONS)
    conn.execute(_DDL_EFFECTS)
    try:
        yield conn
        conn.commit()
    finally:
        conn.close()


def begin_run(task: str, plan: dict, token_count: int,
              authorization: dict | None = None,
              registry_contract_digest: str | None = None) -> int:
    """Commit plan, registry contract, optional authorization, and intents atomically."""
    digest = plan_digest(plan)
    binding = validate_authorization(authorization, plan) if authorization is not None else None
    with _conn() as conn:
        cursor = conn.execute(
            "INSERT INTO runs (task, plan_json, token_count) VALUES (?, ?, ?)",
            (task, _json(plan), token_count),
        )
        run_id = int(cursor.lastrowid)
        conn.execute("INSERT INTO ledger_runs VALUES (?, ?, ?)",
                     (run_id, digest, len(plan["steps"])))
        if registry_contract_digest is not None:
            if (not isinstance(registry_contract_digest, str)
                    or len(registry_contract_digest) != 64
                    or any(ch not in "0123456789abcdef" for ch in registry_contract_digest)):
                raise RecoveryBlocked("tool registry contract digest must be lowercase SHA-256")
            conn.execute(
                "INSERT INTO registry_bindings (run_id, contract_digest) VALUES (?, ?)",
                (run_id, registry_contract_digest),
            )
        if binding is not None:
            conn.execute(
                "INSERT INTO authorizations "
                "(run_id, authorization_id, approved_plan_digest, policy_digest_or_ref, "
                "authority_ref, decision) VALUES (?, ?, ?, ?, ?, ?)",
                (
                    run_id,
                    binding["authorization_id"],
                    binding["approved_plan_digest"],
                    binding["policy_digest_or_ref"],
                    binding["authority_ref"],
                    1,
                ),
            )
        conn.executemany(
            "INSERT INTO effects (run_id, step, state) VALUES (?, ?, 'INTENT_RECORDED')",
            [(run_id, index) for index, step in enumerate(plan["steps"])
             if step["type"] == "tool"],
        )
    return run_id


def bound_effects(run_id: int, plan: dict,
                  authorization: dict | None = None,
                  registry_contract_digest: str | None = None) -> list[dict]:
    """Verify plan, registry contract, authorization, and effects before dispatch."""
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

        if registry_contract_digest is not None:
            registry_row = conn.execute(
                "SELECT contract_digest FROM registry_bindings WHERE run_id=?",
                (run_id,),
            ).fetchone()
            if registry_row is None:
                raise RecoveryBlocked(
                    f"run {run_id}: tool registry contract binding is missing"
                )
            if registry_row["contract_digest"] != registry_contract_digest:
                raise RecoveryBlocked(
                    f"run {run_id}: tool registry contract digest mismatch"
                )

        auth_row = conn.execute(
            "SELECT authorization_id, approved_plan_digest, policy_digest_or_ref, "
            "authority_ref, decision FROM authorizations WHERE run_id=?",
            (run_id,),
        ).fetchone()
        if auth_row is not None:
            stored = validate_authorization(_authorization_dict(auth_row), plan)
            if stored["approved_plan_digest"] != row["plan_digest"]:
                raise RecoveryBlocked(f"run {run_id}: authorization/ledger digest mismatch")
            if authorization is not None:
                supplied = validate_authorization(authorization, plan)
                if supplied != stored:
                    raise RecoveryBlocked(f"run {run_id}: authorization binding mismatch")
        elif authorization is not None:
            raise RecoveryBlocked(f"run {run_id}: authorization binding is missing")

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
        registry_binding = conn.execute(
            "SELECT contract_digest FROM registry_bindings WHERE run_id=?",
            (run_id,),
        ).fetchone()
        result["registry_binding"] = (
            dict(registry_binding) if registry_binding is not None else None
        )
        authorization = conn.execute(
            "SELECT authorization_id, approved_plan_digest, policy_digest_or_ref, "
            "authority_ref, decision FROM authorizations WHERE run_id=?",
            (run_id,),
        ).fetchone()
        result["authorization"] = (
            _authorization_dict(authorization) if authorization is not None else None
        )
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
