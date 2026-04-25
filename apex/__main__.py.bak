"""APEX CLI entry point."""
import argparse
import sys
from importlib.metadata import version
from apex.config import load_config
from apex.core.loop import run
from apex.core.state import format_output
from apex.core.types import Tool
from apex.memory import make_memory_tools
from apex.tools import SHELL, READ_FILE, WRITE_FILE, HTTP_GET


def main() -> None:
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
    parser.add_argument("--interactive", "-i", action="store_true", help="Enter interactive prompt mode")
    parser.add_argument("--version", action="version", version=f"apex {version('axiom-apex')}")
    args = parser.parse_args()

    try:
        config = load_config(trace=args.trace, dry_run=args.dry_run)
    except ValueError as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)

    memory_read, memory_write = make_memory_tools(config.db_path)
    registry: dict[str, Tool] = {
        "shell": SHELL,
        "read_file": READ_FILE,
        "write_file": WRITE_FILE,
        "http_get": HTTP_GET,
        "memory_read": memory_read,
        "memory_write": memory_write,
    }

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
