"""Provider abstraction layer for Gemini and Ollama."""
import os
from typing import Protocol, runtime_checkable

_DEFAULT_GEMINI_MODEL = "gemini-3.8-flash"


@runtime_checkable
class Provider(Protocol):
    def complete(self, prompt: str) -> dict:
        """Return {text: str|None, tokens: int, error: str|None}."""
        ...


def _ok(text: str, tokens: int) -> dict:
    return {"text": text, "tokens": tokens, "error": None}


def _err(message: str) -> dict:
    return {"text": None, "tokens": 0, "error": message}


class GeminiProvider:
    def __init__(self, api_key: str, model: str | None = None) -> None:
        self._api_key = api_key
        self._model = model or os.environ.get("GEMINI_MODEL", _DEFAULT_GEMINI_MODEL)
        self.total_tokens = 0

    def complete(self, prompt: str) -> dict:
        import google.genai as genai
        from google.genai import types

        try:
            with genai.Client(
                api_key=self._api_key or None,
                http_options=types.HttpOptions(
                    timeout=60000, retry_options=types.HttpRetryOptions(attempts=1)
                ),
            ) as client:
                response = client.models.generate_content(
                    model=self._model,
                    contents=prompt,
                    config={"max_output_tokens": 8192},
                )
            usage = getattr(response, "usage_metadata", None)
            tokens = int(getattr(usage, "total_token_count", 0) or 0)
            text = response.text or ""
            self.total_tokens += tokens
            return _ok(text, tokens)
        except Exception:
            return _err("Gemini provider request failed")


class OllamaProvider:
    def __init__(self, model: str | None = None) -> None:
        self._base = os.environ.get("OLLAMA_BASE_URL", "http://localhost:11434").rstrip("/")
        self._model = model or os.environ.get("OLLAMA_MODEL", "llama3")
        self.total_tokens = 0

    def complete(self, prompt: str) -> dict:
        import json
        import urllib.request

        try:
            payload = json.dumps(
                {
                    "model": self._model,
                    "prompt": prompt,
                    "stream": False,
                    "options": {"temperature": 0.2},
                }
            ).encode()
            request = urllib.request.Request(
                f"{self._base}/api/generate",
                data=payload,
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            with urllib.request.urlopen(request, timeout=300) as response:
                data = json.loads(response.read())
            text = data.get("response", "")
            prompt_tokens = int(data.get("prompt_eval_count") or 0)
            output_tokens = int(data.get("eval_count") or 0)
            tokens = prompt_tokens + output_tokens
            if tokens == 0:
                tokens = len(prompt.split()) + len(text.split())
            self.total_tokens += tokens
            return _ok(text, tokens)
        except Exception:
            return _err("Ollama provider request failed")


def get_provider(
    api_key: str = "", *, provider: str | None = None, model: str | None = None
) -> GeminiProvider | OllamaProvider:
    provider = (provider or os.environ.get("LLM_PROVIDER", "gemini")).lower()
    if provider == "ollama":
        return OllamaProvider(model=model)
    if provider == "gemini":
        return GeminiProvider(api_key=api_key, model=model)
    raise ValueError(f"Unsupported LLM_PROVIDER: {provider}")
