"""ChatGPT planning through the OpenAI Responses API; no new dependency."""
import json
import os
from urllib.request import Request, urlopen


class ChatGPTProvider:
    def __init__(self, api_key: str, model: str | None = None) -> None:
        self._api_key = api_key
        self._model = model or os.environ.get("OPENAI_MODEL", "chat-latest")
        self.total_tokens = 0

    def complete(self, prompt: str) -> dict:
        if not self._api_key:
            return {"text": None, "tokens": 0, "error": "OPENAI_API_KEY is required"}
        try:
            request = Request(
                "https://api.openai.com/v1/responses",
                data=json.dumps({"model": self._model, "input": prompt,
                                 "max_output_tokens": 8192, "store": False}).encode(),
                headers={"Content-Type": "application/json",
                         "Authorization": f"Bearer {self._api_key}"},
                method="POST",
            )
            with urlopen(request, timeout=60) as response:
                data = json.loads(response.read())
            if not isinstance(data, dict) or data.get("status") != "completed":
                raise ValueError("incomplete response")
            output = data.get("output")
            if not isinstance(output, list):
                raise ValueError("missing output")
            parts = []
            for message in output:
                if not isinstance(message, dict) or message.get("type") != "message":
                    continue
                for item in message.get("content", []):
                    if isinstance(item, dict) and item.get("type") == "output_text":
                        parts.append(item.get("text"))
            if not parts or any(not isinstance(part, str) for part in parts):
                raise ValueError("missing text")
            usage = data.get("usage") or {}
            tokens = usage.get("total_tokens", 0)
            if type(tokens) is not int or tokens < 0:
                raise ValueError("invalid usage")
            self.total_tokens += tokens
            return {"text": "".join(parts), "tokens": tokens, "error": None}
        except Exception:
            return {"text": None, "tokens": 0, "error": "ChatGPT provider request failed"}
