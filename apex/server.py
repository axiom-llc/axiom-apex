"""APEX HTTP API server — apex serve subcommand."""
from __future__ import annotations

import contextlib
import io
import json
import os
import sqlite3
import sys
from functools import wraps
from pathlib import Path

from flask import Flask, Response, jsonify, request

from apex.config import load_config
from apex.core.loop import run
from apex.core.state import format_output
from apex.core.types import Tool
from apex.history import aggregate_stats, list_runs
from apex.memory import make_memory_tools
from apex.mcp import load_mcp_servers
from apex.tools import HTTP_GET, RAG_MULTI_QUERY, READ_FILE, SHELL, WRITE_FILE
from apex.toolloader import load_tools_dir

try:
    from importlib.metadata import version as _pkg_version
    _VERSION = _pkg_version("axiom-apex")
except Exception:
    _VERSION = "unknown"

_API_KEY: str | None = os.environ.get("APEX_API_KEY")

app = Flask(__name__)
_REGISTRY: dict[str, Tool] = {}
_BASE_CONFIG = None


# ── Auth ──────────────────────────────────────────────────────────────────────

def _require_auth(f):
    @wraps(f)
    def wrapper(*args, **kwargs):
        if _API_KEY is None:
            return f(*args, **kwargs)
        if request.headers.get("X-Apex-Key", "") != _API_KEY:
            return jsonify({"error": "unauthorized"}), 401
        return f(*args, **kwargs)
    return wrapper


# ── Helpers ───────────────────────────────────────────────────────────────────

def _merge_config(overrides: dict | None):
    if not overrides:
        return _BASE_CONFIG
    import dataclasses
    fields = {f.name for f in dataclasses.fields(_BASE_CONFIG)}
    return dataclasses.replace(_BASE_CONFIG, **{k: v for k, v in overrides.items() if k in fields})


def _db_path() -> Path:
    raw = os.environ.get("APEX_DB_PATH")
    return Path(raw).expanduser() if raw else Path.home() / ".apex" / "runs.db"


def _query_run(run_id: int) -> dict | None:
    db = _db_path()
    if not db.exists():
        return None
    with sqlite3.connect(db) as conn:
        conn.row_factory = sqlite3.Row
        row = conn.execute("SELECT * FROM runs WHERE id = ?", (run_id,)).fetchone()
        if row is None:
            return None
        r = dict(row)
        try:
            r["plan_json"] = json.loads(r["plan_json"])
        except Exception:
            pass
        r["events"] = [
            dict(e)
            for e in conn.execute(
                "SELECT * FROM events WHERE run_id = ? ORDER BY step", (run_id,)
            ).fetchall()
        ]
        return r


def _capture_main(fn, argv: list[str]) -> tuple[str, int]:
    """Call a *_main(argv) function, capture stdout, return (text, returncode)."""
    buf = io.StringIO()
    rc = 0
    try:
        with contextlib.redirect_stdout(buf):
            fn(argv)
    except SystemExit as exc:
        rc = int(exc.code) if exc.code is not None else 0
    except Exception as exc:
        return str(exc), 1
    return buf.getvalue(), rc


# ── Routes ────────────────────────────────────────────────────────────────────

@app.route("/health", methods=["GET"])
def health():
    return jsonify({"status": "ok", "version": _VERSION})


@app.route("/run", methods=["POST"])
@_require_auth
def api_run():
    body = request.get_json(silent=True) or {}
    task = body.get("task", "").strip()
    if not task:
        return jsonify({"error": "task is required"}), 400

    config = _merge_config(body.get("config"))
    state = run(task, config=config, registry=_REGISTRY)

    rows = list_runs(1)
    run_id = rows[0]["id"] if rows else None

    plan_dict = None
    _raw_plan = getattr(state, "plan", None)
    if _raw_plan:
        try:
            plan_dict = json.loads(_raw_plan) if isinstance(_raw_plan, str) else _raw_plan
        except Exception:
            plan_dict = str(_raw_plan)

    exit_code = {"HALTED": 0, "ERROR": 1}.get(state.status, 2)
    return jsonify({
        "run_id": run_id,
        "plan": plan_dict,
        "exit_code": exit_code,
        "status": state.status,
        "output": format_output(state),
        "token_count": state.token_count or 0,
        "step_count": len(state.history),
    })


@app.route("/runs", methods=["GET"])
@_require_auth
def api_runs():
    n = request.args.get("n", 20, type=int)
    return jsonify(list_runs(n))


@app.route("/runs/<int:run_id>", methods=["GET"])
@_require_auth
def api_run_detail(run_id: int):
    r = _query_run(run_id)
    if r is None:
        return jsonify({"error": "run not found"}), 404
    return jsonify(r)


@app.route("/replay", methods=["POST"])
@_require_auth
def api_replay():
    body = request.get_json(silent=True) or {}
    run_id = body.get("run_id")
    mode = body.get("mode", "simulate")
    if run_id is None:
        return jsonify({"error": "run_id is required"}), 400
    if mode not in ("simulate", "dry", "live"):
        return jsonify({"error": "mode must be simulate|dry|live"}), 400

    from apex.replay import replay_main
    argv = [str(run_id), "--mode", mode]
    text, rc = _capture_main(replay_main, argv)
    return jsonify({"run_id": run_id, "mode": mode, "exit_code": rc, "output": text})


@app.route("/export", methods=["GET"])
@_require_auth
def api_export():
    fmt = request.args.get("format", "jsonl")
    if fmt not in ("csv", "jsonl"):
        return jsonify({"error": "format must be csv|jsonl"}), 400

    from apex.export import export_main
    argv = ["--format", fmt]
    if request.args.get("since"):
        argv += ["--since", request.args["since"]]
    if request.args.get("fields"):
        argv += ["--fields", request.args["fields"]]
    if request.args.get("events", "false").lower() == "true":
        argv.append("--events")

    text, rc = _capture_main(export_main, argv)
    if rc != 0:
        return jsonify({"error": text.strip()}), 500

    mime = "application/x-ndjson" if fmt == "jsonl" else "text/csv"
    return Response(text, mimetype=mime)


# ── Server entrypoint ─────────────────────────────────────────────────────────

def serve_main(argv: list[str]) -> None:
    import argparse
    p = argparse.ArgumentParser(prog="apex serve")
    p.add_argument("--host", default="127.0.0.1")
    p.add_argument("--port", type=int, default=8080)
    a = p.parse_args(argv)

    global _BASE_CONFIG, _REGISTRY

    try:
        _BASE_CONFIG = load_config()
    except ValueError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        sys.exit(1)

    memory_read, memory_write = make_memory_tools(_BASE_CONFIG.db_path)
    _REGISTRY = {
        "shell": SHELL,
        "read_file": READ_FILE,
        "write_file": WRITE_FILE,
        "http_get": HTTP_GET,
        "rag_multi_query": RAG_MULTI_QUERY,
        "memory_read": memory_read,
        "memory_write": memory_write,
    }
    _REGISTRY.update(load_tools_dir(Path.home() / ".apex" / "tools"))
    mcp_cfgs = json.loads(os.environ.get("APEX_MCP_SERVERS", "[]"))
    if mcp_cfgs:
        _REGISTRY.update(load_mcp_servers(mcp_cfgs))

    if _API_KEY is None:
        print("WARNING: APEX_API_KEY not set — serving without auth", file=sys.stderr)
    else:
        print("Auth: X-Apex-Key required", file=sys.stderr)

    print(f"apex serve {_VERSION}  http://{a.host}:{a.port}", file=sys.stderr)
    app.run(host=a.host, port=a.port, debug=False)
