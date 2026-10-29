"""ASON rollback handler — inspects events for safe compensation availability."""
from __future__ import annotations
import sqlite3
import sys
from pathlib import Path
from .schema import ASONRequest

_DB_PATH = Path.home() / ".apex" / "runs.db"


def generate_rollback(run_id: str, db_path: Path = _DB_PATH) -> ASONRequest | None:
    """Inspect run events; return None when no safe automatic inverse exists.

    write_file requires manual review: compensation authority, durable preimage,
    concurrency/version safety and outcome reconciliation are not defined.
    None means no rollback plan is available, not successful compensation.
    """
    if not db_path.exists():
        return None

    with sqlite3.connect(db_path) as conn:
        rows = conn.execute(
            "SELECT step, tool FROM events WHERE run_id = ? ORDER BY step DESC",
            (run_id,),
        ).fetchall()

    if not rows:
        return None

    for step_num, tool in rows:
        if tool == "write_file":
            print(
                f"rollback: step {step_num} ({tool}): automatic compensation unavailable — "
                "manual review required; compensation authority, durable preimage, "
                "concurrency/version safety and outcome reconciliation contracts are missing",
                file=sys.stderr,
            )
        elif tool == "shell":
            print(
                f"rollback: step {step_num} ({tool}): shell side-effects unresolvable — manual review required",
                file=sys.stderr,
            )

    return None
