import time
import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry
from typing import Optional, Dict, Any


class APIClient:
    """
    Reusable base client for REST API integrations.

    Features:
    - Automatic retries with exponential backoff (5xx, 429, connectivity errors)
    - Rate limiting (requests per second)
    - Configurable timeouts and headers
    - Context manager support
    """

    def __init__(
        self,
        base_url: str,
        api_key: Optional[str] = None,
        requests_per_second: int = 10,
        timeout: int = 30,
        max_retries: int = 5,
        backoff_factor: float = 0.5,
    ):
        self.base_url = base_url.rstrip("/")
        self.timeout = timeout
        self.requests_per_second = requests_per_second
        self._last_call = 0
        self.session = requests.Session()

        headers = {"User-Agent": "Axiom-API-Framework/1.0"}
        if api_key:
            headers["Authorization"] = f"Bearer {api_key}"
        self.session.headers.update(headers)

        retry_strategy = Retry(
            total=max_retries,
            backoff_factor=backoff_factor,
            status_forcelist=[429, 500, 502, 503, 504],
            allowed_methods=["GET", "POST", "PUT", "DELETE", "PATCH"],
            raise_on_status=False,
        )
        adapter = HTTPAdapter(max_retries=retry_strategy)
        self.session.mount("http://", adapter)
        self.session.mount("https://", adapter)

    def _rate_limit(self):
        """Simple interval throttle: enforces minimum gap between requests."""
        now = time.time()
        elapsed = now - self._last_call
        min_interval = 1.0 / self.requests_per_second
        if elapsed < min_interval:
            time.sleep(min_interval - elapsed)
        self._last_call = time.time()

    def _request(self, method: str, endpoint: str, **kwargs) -> requests.Response:
        self._rate_limit()
        url = f"{self.base_url}{endpoint}"
        kwargs.setdefault("timeout", self.timeout)
        return self.session.request(method.upper(), url, **kwargs)

    def get(self, endpoint: str, params: Optional[Dict] = None) -> Any:
        r = self._request("GET", endpoint, params=params)
        r.raise_for_status()
        return r.json()

    def post(
        self,
        endpoint: str,
        data: Optional[Dict] = None,
        json: Optional[Dict] = None,
        params: Optional[Dict] = None,
    ) -> Any:
        r = self._request("POST", endpoint, data=data, json=json, params=params)
        r.raise_for_status()
        return r.json()

    def put(
        self,
        endpoint: str,
        data: Optional[Dict] = None,
        json: Optional[Dict] = None,
        params: Optional[Dict] = None,
    ) -> Any:
        r = self._request("PUT", endpoint, data=data, json=json, params=params)
        r.raise_for_status()
        return r.json()

    def delete(self, endpoint: str) -> None:
        r = self._request("DELETE", endpoint)
        r.raise_for_status()

    def close(self):
        self.session.close()

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.close()
#!/usr/bin/env python3
"""
gemini_client/client.py — Gemini API client built on APIClient
"""

import os
import sys
import json

from api_framework import APIClient

GEMINI_BASE = "https://generativelanguage.googleapis.com"
GEMINI_MODEL = "gemini-2.5-flash"


class GeminiClient(APIClient):
    """Production Gemini API client with retry, rate limiting, and structured output."""

    def __init__(self, api_key: str = None, requests_per_second: int = 5):
        self._gemini_key = api_key or os.environ["GEMINI_API_KEY"]
        super().__init__(
            base_url=GEMINI_BASE,
            requests_per_second=requests_per_second,
            max_retries=5,
            backoff_factor=1.0,
        )
        self.model = GEMINI_MODEL

    def generate(self, prompt: str, system: str = None) -> str:
        """Generate a response. Returns text string."""
        contents = [{"role": "user", "parts": [{"text": prompt}]}]
        body = {"contents": contents}

        if system:
            body["systemInstruction"] = {"parts": [{"text": system}]}

        endpoint = f"/v1beta/models/{self.model}:generateContent"
        params = {"key": self._gemini_key}

        response = self.post(endpoint, json=body, params=params)
        return response["candidates"][0]["content"]["parts"][0]["text"]

    def generate_json(self, prompt: str, system: str = None) -> dict:
        """Generate and parse a JSON response."""
        json_prompt = f"{prompt}\n\nRespond with valid JSON only. No markdown fences."
        raw = self.generate(json_prompt, system=system)
        clean = raw.strip().removeprefix("```json").removesuffix("```").strip()
        return json.loads(clean)


if __name__ == "__main__":
    prompt = sys.argv[1] if len(sys.argv) > 1 else "Summarise the key principles of clean system design in 3 bullet points."

    with GeminiClient() as client:
        print(f"Model : {client.model}")
        print(f"Prompt: {prompt}\n")

        response = client.generate(prompt)
        print("Response:\n", response)

        json_prompt = "List 3 use cases for AI automation in enterprise workflows. Return as JSON array of objects with 'use_case' and 'impact' fields."
        structured = client.generate_json(json_prompt)
        print("\nStructured output:")
        print(json.dumps(structured, indent=2))
