"""Tests for ASON rollback handler."""
import json
import sqlite3
from pathlib import Path
import pytest
from ason.rollback import generate_rollback


def _make_db(tmp_path: Path, events: list[tuple]) -> Path:
    """Create a temp runs.db with given (run_id, step, tool, args_json) rows."""
    path = tmp_path / "runs.db"
    with sqlite3.connect(path) as conn:
        conn.execute(
            "CREATE TABLE events (id INTEGER PRIMARY KEY, run_id TEXT, step INTEGER, tool TEXT, args_json TEXT)"
        )
        conn.executemany(
            "INSERT INTO events (run_id, step, tool, args_json) VALUES (?,?,?,?)",
            events,
        )
    return path


def test_no_db_returns_none(tmp_path):
    assert generate_rollback("run-1", db_path=tmp_path / "nonexistent.db") is None


def test_unknown_run_id_returns_none(tmp_path):
    db = _make_db(tmp_path, [("run-1", 0, "read_file", json.dumps({"path": "/tmp/x"}))])
    assert generate_rollback("run-99", db_path=db) is None


def test_no_reversible_steps_returns_none(tmp_path):
    db = _make_db(tmp_path, [("run-1", 0, "read_file", json.dumps({"path": "/tmp/x"}))])
    assert generate_rollback("run-1", db_path=db) is None


@pytest.mark.parametrize("result", [{"bytes_written": 3}, {"error": "unknown"}, None])
@pytest.mark.parametrize("args", [{"path": "/tmp/out.txt", "content": "new"}, {}])
def test_write_file_requires_manual_review(tmp_path, capsys, result, args):
    db = _make_db(tmp_path, [("run-1", 0, "write_file", json.dumps(args))])
    with sqlite3.connect(db) as conn:
        conn.execute("ALTER TABLE events ADD COLUMN result_json TEXT")
        conn.execute("UPDATE events SET result_json = ?", (json.dumps(result),))

    # No request can reach validation/submission, including the old local-policy
    # delete_file plan, regardless of outcome or availability of a path.
    assert generate_rollback("run-1", db_path=db) is None
    diagnostic = capsys.readouterr().err
    assert "step 0 (write_file)" in diagnostic
    assert "automatic compensation unavailable" in diagnostic
    assert "manual review required" in diagnostic
    for contract in ("authority", "durable preimage", "concurrency/version safety", "outcome reconciliation"):
        assert contract in diagnostic


def test_mixed_history_returns_no_partial_plan(tmp_path, capsys):
    db = _make_db(tmp_path, [
        ("run-1", 0, "write_file", json.dumps({"path": "/tmp/a"})),
        ("run-1", 1, "shell", json.dumps({"cmd": "echo example"})),
        ("run-1", 2, "read_file", json.dumps({"path": "/tmp/a"})),
        ("run-1", 3, "write_file", json.dumps({"path": "/tmp/b"})),
    ])
    assert generate_rollback("run-1", db_path=db) is None
    diagnostics = capsys.readouterr().err.splitlines()
    assert len(diagnostics) == 3
    assert "step 3 (write_file)" in diagnostics[0]
    assert "step 1 (shell)" in diagnostics[1]
    assert "step 0 (write_file)" in diagnostics[2]


def test_shell_step_flagged_not_reversed(tmp_path, capsys):
    db = _make_db(tmp_path, [("run-1", 0, "shell", json.dumps({"cmd": "rm -rf /tmp/x"}))])
    req = generate_rollback("run-1", db_path=db)
    assert req is None
    assert "manual review" in capsys.readouterr().err
