"""Provider abstraction layer — unified LLM interface over Gemini and Ollama."""
import os
import time
from typing import Protocol, runtime_checkable

_RETRY_DELAYS = [1, 2, 4, 8]  # deterministic backoff seconds


@runtime_checkable
class Provider(Protocol):
    def complete(self, prompt: str) -> dict:
        """Returns {text: str, tokens: int, error: str|None}"""
        ...


def _ok(text: str, tokens: int) -> dict:
    return {"text": text, "tokens": tokens, "error": None}


def _err(msg: str) -> dict:
    return {"text": None, "tokens": 0, "error": msg}


class GeminiProvider:
    def __init__(self, api_key: str) -> None:
        self._api_key = api_key
        self.total_tokens = 0

    def complete(self, prompt: str) -> dict:
        import google.genai as genai
        last_err = None
        for attempt, delay in enumerate([0] + _RETRY_DELAYS, start=1):
            if delay:
                time.sleep(delay)
            try:
                client = genai.Client(api_key=self._api_key or None)
                response = client.models.generate_content(
                    model="gemini-2.5-flash",
                    contents=prompt,
                    config={"temperature": 0.2, "max_output_tokens": 8192},
                )
                tokens = response.usage_metadata.total_token_count
                self.total_tokens += tokens
                return _ok(response.text, tokens)
            except Exception as e:
                last_err = str(e)
        return _err(f"GeminiProvider failed after {len(_RETRY_DELAYS)+1} attempts: {last_err}")


class OllamaProvider:
    def __init__(self) -> None:
        self._base = os.environ.get("OLLAMA_BASE_URL", "http://localhost:11434")
        self._model = os.environ.get("OLLAMA_MODEL", "llama3")
        self.total_tokens = 0

    def complete(self, prompt: str) -> dict:
        import json
        import urllib.request
        last_err = None
        for attempt, delay in enumerate([0] + _RETRY_DELAYS, start=1):
            if delay:
                time.sleep(delay)
            try:
                payload = json.dumps({
                    "model": self._model,
                    "prompt": prompt,
                    "stream": False,
                    "options": {"temperature": 0.2},
                }).encode()
                req = urllib.request.Request(
                    f"{self._base}/api/generate",
                    data=payload,
                    headers={"Content-Type": "application/json"},
                    method="POST",
                )
                with urllib.request.urlopen(req, timeout=300) as resp:
                    data = json.loads(resp.read())
                text = data.get("response", "")
                tokens = data.get("eval_count", len(text.split()))
                self.total_tokens += tokens
                return _ok(text, tokens)
            except Exception as e:
                last_err = str(e)
        return _err(f"OllamaProvider failed after {len(_RETRY_DELAYS)+1} attempts: {last_err}")


def get_provider(api_key: str = "") -> GeminiProvider | OllamaProvider:
    provider = os.environ.get("LLM_PROVIDER", "gemini").lower()
    if provider == "ollama":
        return OllamaProvider()
    return GeminiProvider(api_key=api_key)
