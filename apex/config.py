"""Runtime configuration — resolved once at startup, passed explicitly."""
import os
from dataclasses import dataclass
from pathlib import Path

@dataclass(frozen=True)
class Config:
    api_key: str
    db_path: Path
    trace: bool
    dry_run: bool
    full_trace: bool
    trace_path: Path | None
    paranoid: bool

def load_config(*, trace: bool = False, dry_run: bool = False, full_trace: bool = False, trace_path: Path | None = None, paranoid: bool = False) -> Config:
    """Resolve config from environment. Raises ValueError on missing required values."""
    api_key = os.environ.get("GEMINI_API_KEY", "")
    if not api_key:
        raise ValueError("GEMINI_API_KEY environment variable not set")
    db_path = Path(os.environ.get("APEX_DB_PATH", Path.home() / ".apex" / "memory.db"))
    return Config(api_key=api_key, db_path=db_path, trace=trace, dry_run=dry_run, full_trace=full_trace, trace_path=trace_path, paranoid=paranoid)
