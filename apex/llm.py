"""Compatibility LLM shim delegating to :mod:`apex.providers`."""
from apex.providers import get_provider


def gemini_complete(
    prompt: str, *, api_key: str, provider: str | None = None, model: str | None = None
) -> dict:
    """Complete one prompt through the selected provider/profile."""
    return get_provider(api_key=api_key, provider=provider, model=model).complete(prompt)
