# AXIOM API

Reusable Python HTTP client foundation for REST integrations. It centralizes
bounded retry policy, interval throttling, authentication headers, and session
lifecycle management without prescribing an application architecture.

![CI](https://github.com/axiom-llc/axiom-api/actions/workflows/ci.yml/badge.svg)

## Current scope

Version `0.1.1` provides an `APIClient` and a Gemini example client. The
repository validates Python 3.11 and 3.12 in CI; its tests mock outbound HTTP.

`APIClient` provides:

- retry handling for 429, selected 5xx responses, and connection failures;
- a configurable minimum interval between calls;
- a `requests.Session` context-manager lifecycle;
- Bearer-token headers that subclasses may replace; and
- redirect refusal before a provider credential header can be forwarded.

Retries are a transport behavior, not an end-to-end delivery guarantee. Rate
limiting is process-local and does not coordinate concurrent clients or replace
a provider's quota controls.

## Install

```bash
git clone https://github.com/axiom-llc/axiom-api
cd axiom-api
python -m pip install -e .
```

---

## Usage

```python
from api_framework import APIClient

with APIClient(
    base_url="https://api.example.com",
    api_key="your-key",
    requests_per_second=10,
) as client:
    data   = client.get("/endpoint", params={"key": "value"})
    result = client.post("/endpoint", json={"field": "value"})
```

---

## Retry safety

Status and read-error retries default to idempotent HTTP methods (GET, HEAD,
OPTIONS, PUT, DELETE, TRACE). POST and PATCH are not retried after a response or
read failure, since the server may already have applied their side effects.
Connection failures before sending a request may still retry. Unclassified
errors are not retried. Set `max_retries=0` to disable all retries.

Only opt in to POST/PATCH retries when the endpoint guarantees idempotency,
for example with a server-supported idempotency key:

```python
with APIClient("https://api.example.com", retry_methods=frozenset({"GET", "POST"})) as client:
    client.session.headers["Idempotency-Key"] = "unique-operation-id"
    client.post("/orders", json={"quantity": 1})
```

## Authentication patterns

The base client sends `api_key` as a Bearer token header. Override in a
subclass to use any other scheme:

```python
class HMACClient(APIClient):
    def _auth_headers(self) -> dict:
        signature = hmac.new(self.api_key.encode(), digestmod="sha256").hexdigest()
        return {"X-Signature": signature}
```

---

## Included example

`gemini_client/` is a Gemini API example built on `APIClient`. It sends the key
in `x-goog-api-key`, refuses redirects, and leaves POST generation requests out
of the default retry set.

```bash
export GEMINI_API_KEY=your-key
python -m gemini_client.client "explain the CAP theorem in 3 bullet points"
```

---

## Validation

```bash
python -m pip install -e ".[dev]"
python -m pytest tests/ -q
```

All tests mock outbound HTTP; no API key is required. CI runs on Python 3.11
and 3.12 for pushes.

---

## Extending

```python
from api_framework import APIClient

class StripeClient(APIClient):
    def list_customers(self, limit: int = 10) -> dict:
        return self.get("/v1/customers", params={"limit": limit})

    def create_charge(self, amount: int, currency: str, source: str) -> dict:
        return self.post("/v1/charges", json={
            "amount": amount,
            "currency": currency,
            "source": source,
        })
```

---

## Provider boundary validation

Send Gemini credentials in `x-goog-api-key`, never URL query parameters. Refuse
redirects so provider-specific headers cannot reach another origin. POST
generation requests are not implicitly retried.

Manual validation on 2026-09-11 exercised `GeminiClient.generate` against
`gemini-2.5-flash`, then an intentionally nonexistent model. Generation succeeded;
the provider returned HTTP 404 for the invalid model, without the key appearing
in the exception text. Offline tests cover redirect refusal and retry behavior.
Keep real provider credentials out of CI.

## Related AXIOM components

- [APEX](https://github.com/axiom-llc/axiom-apex) — execution runtime.
- [ASON](https://github.com/axiom-llc/axiom-ason) — pre-execution policy enforcement.
- [RAG](https://github.com/axiom-llc/axiom-rag) — retrieval/storage HTTP service and library.

## License

[MIT](LICENSE) — [AXIOM LLC](https://axiom-llc.github.io)
