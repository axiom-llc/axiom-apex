"""LLM shim — delegates to apex.providers. Preserved for import compatibility."""
import os
from apex.providers import get_provider

def gemini_complete(prompt: str, *, api_key: str) -> dict:
    return get_provider(api_key=api_key).complete(prompt)
