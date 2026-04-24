"""LLM provider implementations — Gemini (default) and Ollama.

Set LLM_PROVIDER=ollama and OLLAMA_MODEL=<model> to use local Ollama.
Ollama base URL defaults to http://localhost:11434.
"""
import os

import google.genai as genai

_OLLAMA_BASE = os.environ.get("OLLAMA_BASE_URL", "http://localhost:11434")
_OLLAMA_MODEL = os.environ.get("OLLAMA_MODEL", "llama3")


def _gemini_complete(prompt: str, *, api_key: str) -> dict:
    """Call Gemini and return text + token count."""
    client = genai.Client(api_key=api_key or None)
    response = client.models.generate_content(
        model="gemini-2.5-flash",
        contents=prompt,
        config={
            "temperature": 0.2,
            "max_output_tokens": 8192,
        },
    )
    return {
        "text": response.text,
        "tokens": response.usage_metadata.total_token_count,
    }


def _ollama_complete(prompt: str) -> dict:
    """Call Ollama /api/generate and return text + estimated token count."""
    import json
    import urllib.request

    payload = json.dumps({
        "model": _OLLAMA_MODEL,
        "prompt": prompt,
        "stream": False,
        "options": {"temperature": 0.2},
    }).encode()

    req = urllib.request.Request(
        f"{_OLLAMA_BASE}/api/generate",
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=300) as resp:
        data = json.loads(resp.read())

    text = data.get("response", "")
    tokens = data.get("eval_count", len(text.split()))
    return {"text": text, "tokens": tokens}


def gemini_complete(prompt: str, *, api_key: str) -> dict:
    """Dispatch to configured LLM provider."""
    provider = os.environ.get("LLM_PROVIDER", "gemini").lower()
    if provider == "ollama":
        return _ollama_complete(prompt)
    return _gemini_complete(prompt, api_key=api_key)
