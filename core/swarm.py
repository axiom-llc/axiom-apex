"""Swarm coordinator — parallel task dispatch with optional human-in-loop gate."""
import json
import os
import sqlite3
import subprocess
import sys
import uuid
from contextlib import contextmanager
from pathlib import Path
from time import time


@contextmanager
def _conn(db_path: Path):
    db_path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(db_path)
    try:
        yield conn
        conn.commit()
    finally:
        conn.close()


def _ensure_schema(db_path: Path) -> None:
    with _conn(db_path) as conn:
        conn.execute("""
            CREATE TABLE IF NOT EXISTS swarm_runs (
                run_id  TEXT NOT NULL,
                task    TEXT NOT NULL,
                status  TEXT NOT NULL,
                pid     INTEGER,
                ts      REAL NOT NULL
            )
        """)


def _record(db_path: Path, run_id: str, task: str, status: str, pid: int | None) -> None:
    with _conn(db_path) as conn:
        conn.execute(
            "INSERT INTO swarm_runs (run_id, task, status, pid, ts) VALUES (?, ?, ?, ?, ?)",
            (run_id, task, status, pid, time()),
        )


def run_swarm(
    tasks: list[str],
    *,
    workers: int = 4,
    human_loop: bool = False,
    db_path: Path,
    apex_bin: str,
    extra_args: list[str] | None = None,
) -> int:
    """Dispatch tasks as parallel apex subprocesses. Returns number of failures."""
    _ensure_schema(db_path)
    run_id = str(uuid.uuid4())
    extra_args = extra_args or []
    failures = 0

    batches = [tasks[i:i + workers] for i in range(0, len(tasks), workers)]

    for batch in batches:
        if human_loop:
            print(f"\n[swarm] Next batch ({len(batch)} task(s)):")
            for i, t in enumerate(batch, 1):
                print(f"  {i}. {t}")
            try:
                resp = input("[swarm] Press Enter to dispatch, or 'skip' to skip batch: ").strip().lower()
            except (EOFError, KeyboardInterrupt):
                print("\n[swarm] Aborted.")
                break
            if resp == "skip":
                for t in batch:
                    _record(db_path, run_id, t, "skipped", None)
                continue

        procs: list[tuple[str, subprocess.Popen]] = []
        for task in batch:
            cmd = [apex_bin] + extra_args + [task]
            proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            _record(db_path, run_id, task, "running", proc.pid)
            procs.append((task, proc))

        for task, proc in procs:
            stdout, stderr = proc.communicate()
            status = "ok" if proc.returncode == 0 else "error"
            _record(db_path, run_id, task, status, proc.pid)
            print(f"\n[swarm:{status}] {task}")
            if stdout.strip():
                print(stdout.strip())
            if stderr.strip():
                print(stderr.strip(), file=sys.stderr)
            if proc.returncode != 0:
                failures += 1

    print(f"\n[swarm] run_id={run_id} tasks={len(tasks)} failures={failures}")
    return failures
