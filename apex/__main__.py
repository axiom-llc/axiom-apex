"""APEX CLI entry point."""
from pathlib import Path
import argparse
import sys
from importlib.metadata import version
from apex.config import load_config
from apex.core.loop import run
from apex.core.state import format_output
from apex.core.types import Tool
from apex.memory import make_memory_tools
from apex.toolloader import load_tools_dir
from apex.mcp import load_mcp_servers, mcp_tool_docs
from apex.tools import SHELL, READ_FILE, WRITE_FILE, HTTP_GET, RAG_MULTI_QUERY


def main() -> None:
    if len(sys.argv) > 1 and sys.argv[1] == "swarm":
        from apex.core.swarm import run_swarm
        import argparse as _ap
        sp = _ap.ArgumentParser(prog="apex swarm")
        sp.add_argument("--tasks", required=True, help="Path to JSON file containing task list")
        sp.add_argument("--workers", type=int, default=4, help="Max parallel workers")
        sp.add_argument("--human-loop", action="store_true", help="Pause for confirmation before each batch")
        sp.add_argument("--trace-path", default=None, help="JSONL trace path passed to each worker")
        sa = sp.parse_args(sys.argv[2:])
        from pathlib import Path as _Path
        tasks = _ap.json.loads(_Path(sa.tasks).read_text()) if hasattr(_ap, "json") else __import__("json").loads(_Path(sa.tasks).read_text())
        apex_bin = sys.argv[0]
        extra = ["--full-trace", "--trace-path", sa.trace_path] if sa.trace_path else []
        failures = run_swarm(tasks, workers=sa.workers, human_loop=sa.human_loop, db_path=_Path.home() / ".apex" / "memory.db", apex_bin=apex_bin, extra_args=extra)
        sys.exit(0 if failures == 0 else 1)

    if len(sys.argv) > 1 and sys.argv[1] == "history":
        from apex.history import list_runs
        import argparse as _ap
        hp = _ap.ArgumentParser(prog="apex history")
        hp.add_argument("-n", type=int, default=20, help="Number of runs to show")
        ha = hp.parse_args(sys.argv[2:])
        rows = list_runs(ha.n)
        if not rows:
            print("no runs recorded")
        else:
            _hdr = "{:>5}  {:>4}  {:>7}  {:>8}  {:>19}  TASK".format("ID","EXIT","TOKENS","WALL(s)","TIMESTAMP")
            print(_hdr)
            for r in rows:
                task_short = r["task"][:60] + ("..." if len(r["task"]) > 60 else "")
                print(f'{r["id"]:>5}  {r["exit_code"]:>4}  {r["token_count"]:>7}  {r["wall_seconds"]:>8.3f}  {r["timestamp"]:>19}  {task_short}')
        sys.exit(0)
    if len(sys.argv) > 1 and sys.argv[1] == "stats":
        from apex.history import aggregate_stats
        import json as _json
        print(_json.dumps(aggregate_stats(), indent=2))
        sys.exit(0)
    if len(sys.argv) > 1 and sys.argv[1] == "templates":
        from apex.templates import templates_main
        templates_main(sys.argv[2:])
        sys.exit(0)

    parser = argparse.ArgumentParser(
        prog="apex",
        description="APEX — Agentic Process Executor",
    )
    parser.add_argument("task", nargs="*", help="Task description")
    parser.add_argument("--dry-run", action="store_true", help="Print plan JSON without executing")
    parser.add_argument("--trace", action="store_true", help="Log each step result to stderr")
    parser.add_argument("--full-trace", action="store_true", help="Write JSONL trace events to file or stderr")
    parser.add_argument("--trace-path", default=None, help="Path to JSONL trace output file (default: stderr)")
    parser.add_argument("--paranoid", action="store_true", help="Audit plan for dangerous operations before execution")
    parser.add_argument("--interactive", "-i", action="store_true", help="Enter interactive prompt mode")
    parser.add_argument("--version", action="version", version=f"apex {version('axiom-apex')}")
    args = parser.parse_args()

    try:
        from pathlib import Path
        config = load_config(
            trace=args.trace,
            dry_run=args.dry_run,
            full_trace=args.full_trace,
            trace_path=Path(args.trace_path) if args.trace_path else None, paranoid=args.paranoid
        )
    except ValueError as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)

    memory_read, memory_write = make_memory_tools(config.db_path)
    registry: dict[str, Tool] = {
        "shell": SHELL,
        "read_file": READ_FILE,
        "write_file": WRITE_FILE,
        "http_get": HTTP_GET,
        "rag_multi_query": RAG_MULTI_QUERY,
        "memory_read": memory_read,
        "memory_write": memory_write,
    }
    tools_dir = Path.home() / ".apex" / "tools"
    registry.update(load_tools_dir(tools_dir))
    _mcp_configs = __import__('json').loads(__import__('os').environ.get('APEX_MCP_SERVERS', '[]'))
    if _mcp_configs:
        _mcp_tools = load_mcp_servers(_mcp_configs)
        registry.update(_mcp_tools)

    if args.interactive:
        print(f"APEX {version('axiom-apex')} — interactive mode. Ctrl-D or 'exit' to quit.")
        while True:
            try:
                task = input("apex> ").strip()
            except (EOFError, KeyboardInterrupt):
                print()
                break
            if not task:
                continue
            if task.lower() in ("exit", "quit"):
                break
            state = run(task, config=config, registry=registry)
            print(format_output(state))
        sys.exit(0)

    if not args.task:
        parser.print_help()
        sys.exit(1)

    task = " ".join(args.task)
    final_state = run(task, config=config, registry=registry)
    print(format_output(final_state))

    match final_state.status:
        case "HALTED":
            sys.exit(0)
        case "ERROR":
            sys.exit(1)
        case _:
            sys.exit(2)


if __name__ == "__main__":
    main()
