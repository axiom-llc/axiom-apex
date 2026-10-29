"""Minimal durable AXIOM operational harness vertical slice.

This module owns generic task/lease/attempt/acceptance/commit state and is
independent of domain applications. It supports hard-zero-spend work only.
"""
from __future__ import annotations

from dataclasses import asdict, dataclass
from hashlib import sha256
import json
from pathlib import Path
import sqlite3
import time
from typing import Literal
from uuid import uuid4

SCHEMA_VERSION = 1
TASK_STATES = frozenset({"READY", "LEASED", "BLOCKED", "UNKNOWN", "FAILED", "COMMITTED"})
ATTEMPT_OUTCOMES = frozenset({"FAILED", "REJECTED", "UNKNOWN", "ACCEPTED"})
MUTATION_LEVEL = {f"M{i}": i for i in range(5)}


class HarnessError(RuntimeError):
    """Base harness error."""


class ConflictError(HarnessError):
    """An immutable identity conflicts with existing state."""


class EligibilityError(HarnessError):
    """A resource or context violates hard task constraints."""


class LeaseError(HarnessError):
    """A lease cannot be acquired or used."""


class StateError(HarnessError):
    """Persisted state is inconsistent with the requested transition."""


def _now(value: int | None = None) -> int:
    return int(time.time()) if value is None else int(value)


def _sha256(data: bytes) -> str:
    return sha256(data).hexdigest()


def _canonical_json(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True)


def _spec_hash(value: object) -> str:
    return _sha256(_canonical_json(value).encode("utf-8"))


def _normalize_capabilities(values: tuple[str, ...]) -> tuple[str, ...]:
    cleaned = tuple(sorted({value.strip() for value in values if value.strip()}))
    if len(cleaned) != len(values):
        raise ValueError("capabilities must be non-empty, unique strings")
    return cleaned


def _validate_digest(value: str) -> str:
    value = value.strip().lower()
    if len(value) != 64 or any(ch not in "0123456789abcdef" for ch in value):
        raise ValueError("expected_result_sha256 must be a 64-character SHA-256 hex digest")
    return value


@dataclass(frozen=True, slots=True)
class TaskSpec:
    task_id: str
    intent_ref: str
    domain: str
    capabilities: tuple[str, ...]
    expected_result_sha256: str
    mutation_class: str = "M0"
    cash_ceiling: float = 0.0
    context_budget: int | None = None
    retry_budget: int = 0

    def __post_init__(self) -> None:
        for name in ("task_id", "intent_ref", "domain"):
            value = getattr(self, name).strip()
            if not value:
                raise ValueError(f"{name} is required")
            object.__setattr__(self, name, value)
        object.__setattr__(self, "capabilities", _normalize_capabilities(self.capabilities))
        object.__setattr__(self, "expected_result_sha256", _validate_digest(self.expected_result_sha256))
        if self.mutation_class not in MUTATION_LEVEL:
            raise ValueError("mutation_class must be M0..M4")
        if self.cash_ceiling != 0.0:
            raise ValueError("this vertical slice permits only a hard $0.00 cash ceiling")
        if self.context_budget is not None and self.context_budget < 0:
            raise ValueError("context_budget must be >= 0")
        if self.retry_budget < 0:
            raise ValueError("retry_budget must be >= 0")


@dataclass(frozen=True, slots=True)
class ResourceSpec:
    resource_id: str
    capabilities: tuple[str, ...]
    maximum_mutation_class: str = "M0"
    hard_zero_spend_eligible: bool = True
    context_limit: int | None = None

    def __post_init__(self) -> None:
        resource_id = self.resource_id.strip()
        if not resource_id:
            raise ValueError("resource_id is required")
        object.__setattr__(self, "resource_id", resource_id)
        object.__setattr__(self, "capabilities", _normalize_capabilities(self.capabilities))
        if self.maximum_mutation_class not in MUTATION_LEVEL:
            raise ValueError("maximum_mutation_class must be M0..M4")
        if self.context_limit is not None and self.context_limit < 0:
            raise ValueError("context_limit must be >= 0")


@dataclass(frozen=True, slots=True)
class LeaseRecord:
    lease_id: str
    task_id: str
    resource_id: str
    context_hash: str
    context_size: int
    acquired_at: int
    expires_at: int


@dataclass(frozen=True, slots=True)
class AttemptRecord:
    attempt_id: str
    task_id: str
    resource_id: str
    lease_id: str
    context_hash: str
    result_digest: str | None
    result_ref: str | None
    outcome: str
    retry_safe: bool
    started_at: int
    completed_at: int


_SCHEMA = f"""
CREATE TABLE IF NOT EXISTS schema_info (
    singleton INTEGER PRIMARY KEY CHECK(singleton = 1),
    version INTEGER NOT NULL
);
INSERT OR IGNORE INTO schema_info(singleton, version) VALUES(1, {SCHEMA_VERSION});

CREATE TABLE IF NOT EXISTS tasks (
    task_id TEXT PRIMARY KEY,
    spec_json TEXT NOT NULL,
    spec_hash TEXT NOT NULL,
    created_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS task_state (
    task_id TEXT PRIMARY KEY REFERENCES tasks(task_id),
    state TEXT NOT NULL CHECK(state IN ('READY','LEASED','BLOCKED','UNKNOWN','FAILED','COMMITTED')),
    active_lease_id TEXT,
    canonical_attempt_id TEXT,
    updated_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS resources (
    resource_id TEXT PRIMARY KEY,
    spec_json TEXT NOT NULL,
    spec_hash TEXT NOT NULL,
    created_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS leases (
    lease_id TEXT PRIMARY KEY,
    task_id TEXT NOT NULL REFERENCES tasks(task_id),
    resource_id TEXT NOT NULL REFERENCES resources(resource_id),
    context_hash TEXT NOT NULL,
    context_size INTEGER NOT NULL CHECK(context_size >= 0),
    acquired_at INTEGER NOT NULL,
    expires_at INTEGER NOT NULL,
    released_at INTEGER
);
CREATE UNIQUE INDEX IF NOT EXISTS one_active_lease_per_task
    ON leases(task_id) WHERE released_at IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS one_active_lease_per_resource
    ON leases(resource_id) WHERE released_at IS NULL;
CREATE TABLE IF NOT EXISTS attempts (
    attempt_id TEXT PRIMARY KEY,
    task_id TEXT NOT NULL REFERENCES tasks(task_id),
    resource_id TEXT NOT NULL REFERENCES resources(resource_id),
    lease_id TEXT NOT NULL UNIQUE REFERENCES leases(lease_id),
    context_hash TEXT NOT NULL,
    result_digest TEXT,
    result_ref TEXT,
    outcome TEXT NOT NULL CHECK(outcome IN ('FAILED','REJECTED','UNKNOWN','ACCEPTED')),
    retry_safe INTEGER NOT NULL CHECK(retry_safe IN (0,1)),
    started_at INTEGER NOT NULL,
    completed_at INTEGER NOT NULL
);
CREATE TRIGGER IF NOT EXISTS attempts_immutable_update
BEFORE UPDATE ON attempts BEGIN SELECT RAISE(ABORT, 'attempts are immutable'); END;
CREATE TRIGGER IF NOT EXISTS attempts_immutable_delete
BEFORE DELETE ON attempts BEGIN SELECT RAISE(ABORT, 'attempts are immutable'); END;
CREATE TRIGGER IF NOT EXISTS tasks_immutable_update
BEFORE UPDATE ON tasks BEGIN SELECT RAISE(ABORT, 'task specs are immutable'); END;
CREATE TRIGGER IF NOT EXISTS tasks_immutable_delete
BEFORE DELETE ON tasks BEGIN SELECT RAISE(ABORT, 'task specs are immutable'); END;
CREATE TRIGGER IF NOT EXISTS resources_immutable_update
BEFORE UPDATE ON resources BEGIN SELECT RAISE(ABORT, 'resource specs are immutable'); END;
CREATE TRIGGER IF NOT EXISTS resources_immutable_delete
BEFORE DELETE ON resources BEGIN SELECT RAISE(ABORT, 'resource specs are immutable'); END;
CREATE TABLE IF NOT EXISTS canonical_results (
    task_id TEXT PRIMARY KEY REFERENCES tasks(task_id),
    attempt_id TEXT NOT NULL UNIQUE REFERENCES attempts(attempt_id),
    receipt_json TEXT NOT NULL,
    committed_at INTEGER NOT NULL
);
"""


class HarnessStore:
    """SQLite/WAL authority for the generic vertical slice."""

    def __init__(self, path: str | Path):
        self.path = str(path)
        self.cx = sqlite3.connect(self.path, timeout=5.0, isolation_level=None)
        self.cx.row_factory = sqlite3.Row
        self.cx.execute("PRAGMA foreign_keys=ON")
        self.cx.execute("PRAGMA journal_mode=WAL")
        self.cx.execute("PRAGMA synchronous=FULL")
        self.cx.executescript(_SCHEMA)
        row = self.cx.execute("SELECT version FROM schema_info WHERE singleton=1").fetchone()
        if row is None or row["version"] != SCHEMA_VERSION:
            self.close()
            raise StateError("unsupported harness schema version")

    def close(self) -> None:
        self.cx.close()

    def __enter__(self) -> "HarnessStore":
        return self

    def __exit__(self, exc_type, exc, tb) -> None:
        self.close()

    def _begin(self) -> None:
        self.cx.execute("BEGIN IMMEDIATE")

    def _commit(self) -> None:
        self.cx.execute("COMMIT")

    def _rollback(self) -> None:
        if self.cx.in_transaction:
            self.cx.execute("ROLLBACK")

    @staticmethod
    def _task_json(spec: TaskSpec) -> str:
        return _canonical_json(asdict(spec))

    @staticmethod
    def _resource_json(spec: ResourceSpec) -> str:
        return _canonical_json(asdict(spec))

    @staticmethod
    def _decode_task(raw: str) -> TaskSpec:
        value = json.loads(raw)
        value["capabilities"] = tuple(value["capabilities"])
        return TaskSpec(**value)

    @staticmethod
    def _decode_resource(raw: str) -> ResourceSpec:
        value = json.loads(raw)
        value["capabilities"] = tuple(value["capabilities"])
        return ResourceSpec(**value)

    def submit_task(self, spec: TaskSpec, *, now: int | None = None) -> str:
        raw = self._task_json(spec)
        digest = _spec_hash(json.loads(raw))
        timestamp = _now(now)
        try:
            self._begin()
            row = self.cx.execute("SELECT spec_hash FROM tasks WHERE task_id=?", (spec.task_id,)).fetchone()
            if row:
                if row["spec_hash"] != digest:
                    raise ConflictError(f"task_id {spec.task_id!r} already has a different immutable spec")
                self._commit()
                return digest
            self.cx.execute(
                "INSERT INTO tasks(task_id,spec_json,spec_hash,created_at) VALUES(?,?,?,?)",
                (spec.task_id, raw, digest, timestamp),
            )
            self.cx.execute(
                "INSERT INTO task_state(task_id,state,updated_at) VALUES(?,?,?)",
                (spec.task_id, "READY", timestamp),
            )
            self._commit()
            return digest
        except Exception:
            self._rollback()
            raise

    def register_resource(self, spec: ResourceSpec, *, now: int | None = None) -> str:
        raw = self._resource_json(spec)
        digest = _spec_hash(json.loads(raw))
        timestamp = _now(now)
        try:
            self._begin()
            row = self.cx.execute(
                "SELECT spec_hash FROM resources WHERE resource_id=?", (spec.resource_id,)
            ).fetchone()
            if row:
                if row["spec_hash"] != digest:
                    raise ConflictError(f"resource_id {spec.resource_id!r} already has a different immutable spec")
                self._commit()
                return digest
            self.cx.execute(
                "INSERT INTO resources(resource_id,spec_json,spec_hash,created_at) VALUES(?,?,?,?)",
                (spec.resource_id, raw, digest, timestamp),
            )
            self._commit()
            return digest
        except Exception:
            self._rollback()
            raise

    def task_spec(self, task_id: str) -> TaskSpec:
        row = self.cx.execute("SELECT spec_json FROM tasks WHERE task_id=?", (task_id,)).fetchone()
        if not row:
            raise KeyError(task_id)
        return self._decode_task(row["spec_json"])

    def resource_spec(self, resource_id: str) -> ResourceSpec:
        row = self.cx.execute("SELECT spec_json FROM resources WHERE resource_id=?", (resource_id,)).fetchone()
        if not row:
            raise KeyError(resource_id)
        return self._decode_resource(row["spec_json"])

    @staticmethod
    def _eligible(task: TaskSpec, resource: ResourceSpec) -> bool:
        if not resource.hard_zero_spend_eligible:
            return False
        if not set(task.capabilities).issubset(resource.capabilities):
            return False
        if MUTATION_LEVEL[resource.maximum_mutation_class] < MUTATION_LEVEL[task.mutation_class]:
            return False
        if task.context_budget is not None:
            if resource.context_limit is not None and resource.context_limit < task.context_budget:
                return False
        return True

    def eligible_resources(self, task_id: str) -> list[str]:
        task = self.task_spec(task_id)
        rows = self.cx.execute("SELECT spec_json FROM resources ORDER BY resource_id").fetchall()
        return [
            resource.resource_id
            for row in rows
            if self._eligible(task, resource := self._decode_resource(row["spec_json"]))
        ]

    def _reap_expired_tx(self, now: int) -> int:
        rows = self.cx.execute(
            "SELECT lease_id,task_id FROM leases WHERE released_at IS NULL AND expires_at<=? ORDER BY lease_id",
            (now,),
        ).fetchall()
        for row in rows:
            self.cx.execute("UPDATE leases SET released_at=? WHERE lease_id=?", (now, row["lease_id"]))
            state = self.cx.execute(
                "SELECT state,active_lease_id FROM task_state WHERE task_id=?", (row["task_id"],)
            ).fetchone()
            if state and state["state"] == "LEASED" and state["active_lease_id"] == row["lease_id"]:
                self.cx.execute(
                    "UPDATE task_state SET state='READY',active_lease_id=NULL,updated_at=? WHERE task_id=?",
                    (now, row["task_id"]),
                )
        return len(rows)

    def reap_expired(self, *, now: int | None = None) -> int:
        timestamp = _now(now)
        try:
            self._begin()
            count = self._reap_expired_tx(timestamp)
            self._commit()
            return count
        except Exception:
            self._rollback()
            raise

    def acquire_lease(
        self,
        task_id: str,
        resource_id: str,
        context: bytes,
        *,
        ttl_seconds: int,
        now: int | None = None,
        lease_id: str | None = None,
    ) -> LeaseRecord:
        if ttl_seconds <= 0:
            raise ValueError("ttl_seconds must be > 0")
        timestamp = _now(now)
        lease_id = lease_id or uuid4().hex
        task = self.task_spec(task_id)
        resource = self.resource_spec(resource_id)
        if not self._eligible(task, resource):
            raise EligibilityError("resource violates task capability, mutation, context, or zero-spend constraints")
        if task.context_budget is not None and len(context) > task.context_budget:
            raise EligibilityError("context exceeds task context budget")
        if resource.context_limit is not None and len(context) > resource.context_limit:
            raise EligibilityError("context exceeds resource context limit")
        context_hash = _sha256(context)
        try:
            self._begin()
            self._reap_expired_tx(timestamp)
            state = self.cx.execute(
                "SELECT state FROM task_state WHERE task_id=?", (task_id,)
            ).fetchone()
            if not state:
                raise KeyError(task_id)
            if state["state"] != "READY":
                raise LeaseError(f"task is not READY: {state['state']}")
            try:
                self.cx.execute(
                    """INSERT INTO leases(
                           lease_id,task_id,resource_id,context_hash,context_size,acquired_at,expires_at)
                       VALUES(?,?,?,?,?,?,?)""",
                    (lease_id, task_id, resource_id, context_hash, len(context), timestamp, timestamp + ttl_seconds),
                )
            except sqlite3.IntegrityError as exc:
                raise LeaseError("task or resource already has an active lease") from exc
            self.cx.execute(
                "UPDATE task_state SET state='LEASED',active_lease_id=?,updated_at=? WHERE task_id=?",
                (lease_id, timestamp, task_id),
            )
            self._commit()
        except Exception:
            self._rollback()
            raise
        return LeaseRecord(
            lease_id, task_id, resource_id, context_hash, len(context), timestamp, timestamp + ttl_seconds
        )

    def record_attempt(
        self,
        lease_id: str,
        *,
        result: bytes | None = None,
        result_ref: str | None = None,
        failure: Literal["failed", "unknown"] | None = None,
        retry_safe: bool = False,
        started_at: int | None = None,
        completed_at: int | None = None,
        attempt_id: str | None = None,
    ) -> AttemptRecord:
        if failure is not None and result is not None:
            raise ValueError("failure and result are mutually exclusive")
        if failure is None and result is None:
            raise ValueError("result is required unless failure is explicit")
        if failure == "unknown" and retry_safe:
            raise ValueError("UNKNOWN can never be marked retry-safe")
        completed = _now(completed_at)
        started = completed if started_at is None else int(started_at)
        if started > completed:
            raise ValueError("started_at must be <= completed_at")
        attempt_id = attempt_id or uuid4().hex
        try:
            self._begin()
            lease = self.cx.execute(
                "SELECT * FROM leases WHERE lease_id=? AND released_at IS NULL", (lease_id,)
            ).fetchone()
            if not lease:
                raise LeaseError("lease is absent or already released")
            if lease["expires_at"] <= completed:
                self._reap_expired_tx(completed)
                raise LeaseError("lease expired before attempt completion")
            state = self.cx.execute(
                "SELECT state,active_lease_id FROM task_state WHERE task_id=?", (lease["task_id"],)
            ).fetchone()
            if not state or state["state"] != "LEASED" or state["active_lease_id"] != lease_id:
                raise StateError("lease is not the task's active authority")
            task_row = self.cx.execute(
                "SELECT spec_json FROM tasks WHERE task_id=?", (lease["task_id"],)
            ).fetchone()
            task = self._decode_task(task_row["spec_json"])
            result_digest: str | None = None
            if failure == "unknown":
                outcome = "UNKNOWN"
                retry_safe = False
            elif failure == "failed":
                outcome = "FAILED"
            else:
                result_digest = _sha256(result or b"")
                outcome = "ACCEPTED" if result_digest == task.expected_result_sha256 else "REJECTED"
            self.cx.execute(
                """INSERT INTO attempts(
                       attempt_id,task_id,resource_id,lease_id,context_hash,result_digest,result_ref,
                       outcome,retry_safe,started_at,completed_at)
                   VALUES(?,?,?,?,?,?,?,?,?,?,?)""",
                (
                    attempt_id, lease["task_id"], lease["resource_id"], lease_id, lease["context_hash"],
                    result_digest, result_ref, outcome, int(retry_safe), started, completed,
                ),
            )
            self.cx.execute("UPDATE leases SET released_at=? WHERE lease_id=?", (completed, lease_id))
            attempts = self.cx.execute(
                "SELECT COUNT(*) AS n FROM attempts WHERE task_id=?", (lease["task_id"],)
            ).fetchone()["n"]
            if outcome == "ACCEPTED":
                next_state = "BLOCKED"  # accepted candidate exists; canonical commit is separate
            elif outcome == "UNKNOWN":
                next_state = "UNKNOWN"
            elif retry_safe and attempts <= task.retry_budget:
                next_state = "READY"
            else:
                next_state = "FAILED"
            self.cx.execute(
                "UPDATE task_state SET state=?,active_lease_id=NULL,updated_at=? WHERE task_id=?",
                (next_state, completed, lease["task_id"]),
            )
            self._commit()
        except Exception:
            self._rollback()
            raise
        return AttemptRecord(
            attempt_id=attempt_id,
            task_id=lease["task_id"],
            resource_id=lease["resource_id"],
            lease_id=lease_id,
            context_hash=lease["context_hash"],
            result_digest=result_digest,
            result_ref=result_ref,
            outcome=outcome,
            retry_safe=bool(retry_safe),
            started_at=started,
            completed_at=completed,
        )

    def commit_accepted(self, attempt_id: str, *, now: int | None = None) -> dict:
        committed = _now(now)
        try:
            self._begin()
            attempt = self.cx.execute("SELECT * FROM attempts WHERE attempt_id=?", (attempt_id,)).fetchone()
            if not attempt:
                raise KeyError(attempt_id)
            if attempt["outcome"] != "ACCEPTED":
                raise StateError("only an ACCEPTED attempt can become canonical")
            existing = self.cx.execute(
                "SELECT receipt_json,attempt_id FROM canonical_results WHERE task_id=?", (attempt["task_id"],)
            ).fetchone()
            if existing:
                if existing["attempt_id"] != attempt_id:
                    raise ConflictError("task already has a different canonical result")
                self._commit()
                return json.loads(existing["receipt_json"])
            state = self.cx.execute(
                "SELECT state FROM task_state WHERE task_id=?", (attempt["task_id"],)
            ).fetchone()
            if not state or state["state"] != "BLOCKED":
                raise StateError("task is not awaiting canonical commit")
            task = self.cx.execute(
                "SELECT spec_hash FROM tasks WHERE task_id=?", (attempt["task_id"],)
            ).fetchone()
            receipt = {
                "schema": "axiom-harness/receipt-v1",
                "task_id": attempt["task_id"],
                "task_spec_hash": task["spec_hash"],
                "attempt_id": attempt_id,
                "resource_id": attempt["resource_id"],
                "context_hash": attempt["context_hash"],
                "result_digest": attempt["result_digest"],
                "result_ref": attempt["result_ref"],
                "outcome": "ACCEPTED",
                "committed_at": committed,
            }
            raw = _canonical_json(receipt)
            self.cx.execute(
                "INSERT INTO canonical_results(task_id,attempt_id,receipt_json,committed_at) VALUES(?,?,?,?)",
                (attempt["task_id"], attempt_id, raw, committed),
            )
            self.cx.execute(
                """UPDATE task_state
                   SET state='COMMITTED',canonical_attempt_id=?,active_lease_id=NULL,updated_at=?
                   WHERE task_id=?""",
                (attempt_id, committed, attempt["task_id"]),
            )
            self._commit()
            return receipt
        except Exception:
            self._rollback()
            raise

    def task_state(self, task_id: str) -> dict:
        row = self.cx.execute("SELECT * FROM task_state WHERE task_id=?", (task_id,)).fetchone()
        if not row:
            raise KeyError(task_id)
        return dict(row)

    def attempts(self, task_id: str) -> list[AttemptRecord]:
        rows = self.cx.execute(
            "SELECT * FROM attempts WHERE task_id=? ORDER BY completed_at,attempt_id", (task_id,)
        ).fetchall()
        return [
            AttemptRecord(
                attempt_id=row["attempt_id"], task_id=row["task_id"], resource_id=row["resource_id"],
                lease_id=row["lease_id"], context_hash=row["context_hash"], result_digest=row["result_digest"],
                result_ref=row["result_ref"], outcome=row["outcome"], retry_safe=bool(row["retry_safe"]),
                started_at=row["started_at"], completed_at=row["completed_at"],
            )
            for row in rows
        ]

    def canonical_result(self, task_id: str) -> dict | None:
        row = self.cx.execute(
            "SELECT receipt_json FROM canonical_results WHERE task_id=?", (task_id,)
        ).fetchone()
        return json.loads(row["receipt_json"]) if row else None

    def check(self) -> dict:
        quick = self.cx.execute("PRAGMA quick_check").fetchone()[0]
        if quick != "ok":
            raise StateError(f"SQLite quick_check failed: {quick}")
        bad = self.cx.execute(
            """SELECT COUNT(*) FROM task_state
               WHERE state NOT IN ('READY','LEASED','BLOCKED','UNKNOWN','FAILED','COMMITTED')"""
        ).fetchone()[0]
        if bad:
            raise StateError("invalid task state")
        return {"ok": True, "schema_version": SCHEMA_VERSION}
