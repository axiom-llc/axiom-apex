"""
apex/cli/templates.py — `apex templates` subcommand group

Registers: apex templates list / info / install / run

Add to main CLI entry point:
    from apex.cli.templates import templates
    app.add_typer(templates, name="templates")

Or if using argparse/click, see integration notes at bottom.
"""

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

try:
    import typer
    from rich.console import Console
    from rich.table import Table
    RICH = True
except ImportError:
    RICH = False

# ── Locate package templates directory ───────────────────
def _templates_dir() -> Path:
    candidates = [
        Path(__file__).parent / "templates",          # apex/templates/ — correct for this layout
        Path(__file__).parent.parent / "apex" / "templates",  # installed package fallback
    ]
    for c in candidates:
        if c.exists():
            return c
    raise FileNotFoundError(
        "templates/ directory not found. Reinstall axiom-apex or check APEX_TEMPLATES_DIR."
    )

def _index() -> list[dict]:
    """Load and return the template registry."""
    override = os.environ.get("APEX_TEMPLATES_DIR")
    base = Path(override) if override else _templates_dir()
    index_file = base / "index.json"
    if not index_file.exists():
        return []
    with open(index_file) as f:
        data = json.load(f)
    return data.get("templates", [])

def _find(name: str) -> dict | None:
    for t in _index():
        if t["name"] == name:
            return t
    return None


# ══════════════════════════════════════════════════════════
# TYPER INTERFACE (preferred)
# ══════════════════════════════════════════════════════════
if RICH:
    templates = typer.Typer(
        name="templates",
        help="Browse, install, and run apex workflow templates.",
        no_args_is_help=True,
    )
    console = Console()

    @templates.command("list")
    def templates_list(
        category: str = typer.Option(None, "--category", "-c", help="Filter by category"),
        tier: str = typer.Option(None, "--tier", "-t", help="Filter by revenue_tier (high|medium|low)"),
    ):
        """List all available templates."""
        entries = _index()
        if category:
            entries = [e for e in entries if e.get("category") == category]
        if tier:
            entries = [e for e in entries if e.get("revenue_tier") == tier]

        table = Table(title="apex templates", show_lines=False, header_style="bold cyan")
        table.add_column("name", style="bold")
        table.add_column("category")
        table.add_column("revenue_tier")
        table.add_column("description", max_width=55)

        for t in entries:
            tier_color = {"high": "green", "medium": "yellow", "low": "dim"}.get(
                t.get("revenue_tier", ""), ""
            )
            table.add_row(
                t["name"],
                t.get("category", ""),
                f"[{tier_color}]{t.get('revenue_tier', '')}[/{tier_color}]",
                t.get("description", ""),
            )
        console.print(table)

    @templates.command("info")
    def templates_info(name: str = typer.Argument(..., help="Template name")):
        """Show full metadata for a template."""
        t = _find(name)
        if not t:
            console.print(f"[red]✗ Template not found: {name}[/red]")
            raise typer.Exit(1)

        console.print(f"\n[bold cyan]{t['name']}[/bold cyan]  ({t.get('category', '')})")
        console.print(f"  {t.get('description', '')}\n")
        console.print(f"  [bold]Revenue tier:[/bold] {t.get('revenue_tier', '')}")
        console.print(f"  [bold]Target buyer:[/bold] {t.get('target_buyer', '')}")
        console.print(f"  [bold]Pricing:[/bold]      {t.get('pricing_model', '')}")

        if t.get("config"):
            console.print("\n  [bold]Config required:[/bold]")
            for c in t["config"]:
                req = " (required)" if c.get("required") else ""
                default = f"  default: {c['default']}" if c.get("default") else ""
                console.print(f"    {c['key']}{req} — {c.get('description','')}{default}")

        if t.get("cron"):
            console.print("\n  [bold]Cron schedules:[/bold]")
            for cr in t["cron"]:
                console.print(f"    {cr['schedule']}  {cr.get('command','')}")

        if t.get("commands"):
            console.print("\n  [bold]Commands:[/bold]")
            for cmd in t["commands"]:
                console.print(f"    {t['file']} {cmd}")
        console.print()

    @templates.command("install")
    def templates_install(
        name: str = typer.Argument(..., help="Template name"),
        dest: str = typer.Option(".", "--dest", "-d", help="Destination directory"),
    ):
        """
        Copy a template script (and lib/) to destination, scaffold config stubs,
        and print the cron entries to add.
        """
        t = _find(name)
        if not t:
            console.print(f"[red]✗ Template not found: {name}[/red]")
            raise typer.Exit(1)

        src_dir = _templates_dir()
        dest_dir = Path(dest).expanduser().resolve()
        dest_dir.mkdir(parents=True, exist_ok=True)

        # Copy script
        src_script = src_dir / t["file"]
        dst_script = dest_dir / t["file"]
        shutil.copy2(src_script, dst_script)
        dst_script.chmod(0o755)
        console.print(f"[green]✓[/green] Copied {t['file']} → {dst_script}")

        # Copy shared lib
        lib_src = src_dir / "lib"
        lib_dst = dest_dir / "lib"
        if lib_src.exists():
            shutil.copytree(lib_src, lib_dst, dirs_exist_ok=True)
            console.print(f"[green]✓[/green] Copied lib/ → {lib_dst}")

        # Scaffold config stubs
        config_dir = Path.home() / ".config" / "apex"
        config_dir.mkdir(parents=True, exist_ok=True)
        if t.get("config"):
            console.print("\n[bold]Config stubs (edit these):[/bold]")
            for c in t["config"]:
                stub = config_dir / c["key"]
                if not stub.exists():
                    default = c.get("default", f"# set your {c['key']} here")
                    stub.write_text(default + "\n")
                    console.print(f"  created  ~/.config/apex/{c['key']}")
                else:
                    console.print(f"  exists   ~/.config/apex/{c['key']}")

        # Print cron lines
        if t.get("cron"):
            console.print("\n[bold]Add to crontab (crontab -e):[/bold]")
            for cr in t["cron"]:
                cmd_str = f"{cr.get('command', '')} >> ~/apex-logs/{t['name']}.log 2>&1".strip()
                console.print(f"  {cr['schedule']}  {dst_script} {cmd_str}")

        console.print(f"\n[bold green]✓ {name} installed.[/bold green] Run: ./{t['file']} --help\n")

    @templates.command("run")
    def templates_run(
        name: str = typer.Argument(..., help="Template name"),
        args: list[str] = typer.Argument(None, help="Arguments passed to the template script"),
    ):
        """
        Run a template from the package (does not require install).
        Example: apex templates run hedge-fund
        """
        t = _find(name)
        if not t:
            console.print(f"[red]✗ Template not found: {name}[/red]")
            raise typer.Exit(1)

        script = _templates_dir() / t["file"]
        if not script.exists():
            console.print(f"[red]✗ Script not found: {script}[/red]")
            raise typer.Exit(1)

        cmd = ["bash", str(script)] + (args or [])
        console.print(f"[dim]▶ {' '.join(cmd)}[/dim]\n")
        result = subprocess.run(cmd)
        raise typer.Exit(result.returncode)


# ══════════════════════════════════════════════════════════
# FALLBACK: plain argparse interface
# If you are not using typer, call templates_main(sys.argv[1:])
# from your CLI entry point.
# ══════════════════════════════════════════════════════════
def templates_main(argv: list[str] | None = None):
    """Minimal argparse fallback for non-typer CLIs."""
    import argparse

    parser = argparse.ArgumentParser(prog="apex templates")
    sub = parser.add_subparsers(dest="cmd")

    sub.add_parser("list",    help="List templates")
    p_info    = sub.add_parser("info",    help="Show template metadata")
    p_install = sub.add_parser("install", help="Install template to directory")
    p_run     = sub.add_parser("run",     help="Run template from package")

    p_info.add_argument("name")
    p_install.add_argument("name")
    p_install.add_argument("--dest", default=".")
    p_run.add_argument("name")
    p_run.add_argument("args", nargs=argparse.REMAINDER)

    args = parser.parse_args(argv)

    if args.cmd == "list":
        for t in _index():
            print(f"  {t['name']:<22} {t.get('category',''):<12} {t.get('description','')}")

    elif args.cmd == "info":
        t = _find(args.name)
        if not t:
            print(f"Template not found: {args.name}"); sys.exit(1)
        print(json.dumps(t, indent=2))

    elif args.cmd == "install":
        # Delegate to typer version if available, else minimal copy
        t = _find(args.name)
        if not t:
            print(f"Template not found: {args.name}"); sys.exit(1)
        src = _templates_dir() / t["file"]
        dst = Path(args.dest).expanduser() / t["file"]
        shutil.copy2(src, dst); dst.chmod(0o755)
        lib_src = _templates_dir() / "lib"
        if lib_src.exists():
            shutil.copytree(lib_src, Path(args.dest) / "lib", dirs_exist_ok=True)
        print(f"✓ Installed {t['file']} → {dst}")

    elif args.cmd == "run":
        t = _find(args.name)
        if not t:
            print(f"Template not found: {args.name}"); sys.exit(1)
        script = _templates_dir() / t["file"]
        sys.exit(subprocess.run(["bash", str(script)] + args.args).returncode)

    else:
        parser.print_help()


if __name__ == "__main__":
    templates_main()
