"""ASON rollback handler — generates reversal plans from apex run events."""
from __future__ import annotations
import json
import sqlite3
import sys
from pathlib import Path
from .schema import ASONRequest, ApexPlan, ApexPlanStep, Policy

_DB_PATH = Path.home() / ".apex" / "runs.db"

_REVERSIBLE: dict[str, str] = {
    "write_file": "delete_file",
}

_FLAGGED = {"shell"}


def generate_rollback(run_id: str, db_path: Path = _DB_PATH) -> ASONRequest | None:
    """Fetch events for run_id; return reversal ASONRequest or None."""
    if not db_path.exists():
        return None

    with sqlite3.connect(db_path) as conn:
        rows = conn.execute(
            "SELECT step, tool, args_json FROM events WHERE run_id = ? ORDER BY step DESC",
            (run_id,),
        ).fetchall()

    if not rows:
        return None

    reversal_steps: list[ApexPlanStep] = []

    for step_num, tool, args_json in rows:
        args: dict = json.loads(args_json) if args_json else {}
        if tool in _REVERSIBLE:
            path = args.get("path")
            if path is None:
                print(
                    f"rollback: step {step_num} ({tool}): no 'path' in args — skipped",
                    file=sys.stderr,
                )
                continue
            reversal_steps.append(
                ApexPlanStep(tool=_REVERSIBLE[tool], args={"path": path})
            )
        elif tool in _FLAGGED:
            print(
                f"rollback: step {step_num} ({tool}): shell side-effects unresolvable — manual review required",
                file=sys.stderr,
            )

    if not reversal_steps:
        return None

    return ASONRequest(
        plan=ApexPlan(steps=reversal_steps),
        policy=Policy(blast_radius="local", rollback_on_failure=False),
    )
