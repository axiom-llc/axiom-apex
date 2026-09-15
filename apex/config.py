"""Resolve immutable runtime configuration once at startup."""
import hashlib
import json
import os
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Config:
    api_key: str
    provider: str
    model: str
    db_path: Path
    trace: bool
    dry_run: bool
    full_trace: bool
    trace_path: Path | None
    audit: bool


def load_config(
    *,
    trace: bool = False,
    dry_run: bool = False,
    full_trace: bool = False,
    trace_path: Path | None = None,
    audit: bool = False,
    require_api_key: bool = True,
) -> Config:
    """Resolve environment configuration and reject unsupported providers."""
    provider = os.environ.get("LLM_PROVIDER", "gemini").lower()
    if provider not in {"gemini", "ollama"}:
        raise ValueError(f"Unsupported LLM_PROVIDER: {provider}")

    model = (
        os.environ.get("GEMINI_MODEL", "gemini-3.8-flash")
        if provider == "gemini"
        else os.environ.get("OLLAMA_MODEL", "llama3")
    )
    api_key = os.environ.get("GEMINI_API_KEY", "")
    if require_api_key and provider == "gemini" and not api_key:
        raise ValueError("GEMINI_API_KEY environment variable not set")

    db_path = Path(
        os.environ.get("APEX_DB_PATH", str(Path.home() / ".apex" / "memory.db"))
    ).expanduser()
    return Config(
        api_key=api_key,
        provider=provider,
        model=model,
        db_path=db_path,
        trace=trace,
        dry_run=dry_run,
        full_trace=full_trace,
        trace_path=trace_path,
        audit=audit,
    )


def execution_profile(config: Config) -> dict[str, object]:
    """Return the secret-free immutable execution profile for evidence binding."""
    return {
        "schema": "apex/execution-profile-v1",
        "provider": config.provider,
        "model": config.model,
        "db_path": str(config.db_path),
        "trace": config.trace,
        "dry_run": config.dry_run,
        "full_trace": config.full_trace,
        "trace_path": str(config.trace_path) if config.trace_path is not None else None,
        "audit": config.audit,
    }


def execution_profile_digest(config: Config) -> str:
    """SHA-256 bind the canonical secret-free execution profile."""
    raw = json.dumps(execution_profile(config), sort_keys=True, separators=(",", ":"), ensure_ascii=True)
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()
