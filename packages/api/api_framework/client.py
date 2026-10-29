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
        *,
        retry_methods: frozenset[str] | None = None,
    ):
        methods = Retry.DEFAULT_ALLOWED_METHODS if retry_methods is None else frozenset(
            method.upper() for method in retry_methods
        )
        if not methods:
            raise ValueError("retry_methods must be non-empty; use max_retries=0 to disable retries")
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
            allowed_methods=methods,
            other=0,
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
        kwargs["allow_redirects"] = False
        response = self.session.request(method.upper(), url, **kwargs)
        if 300 <= response.status_code < 400:
            raise requests.HTTPError("Provider redirect refused", response=response)
        return response

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
