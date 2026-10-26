# APEX installation

[← Project overview](../README.md) · Commands below run from the repository root.

## Install

Python 3.11 or 3.12 is validated. Version 3.2.0 is **unreleased**; the latest published baseline is 3.1.1.
Published distributions are available through [GitHub Releases](https://github.com/axiom-llc/axiom-apex/releases).
The legacy PyPI package does not provide this source architecture; do not use a
bare `pip install axiom-apex` to obtain it.

### Published baseline: APEX 3.1.1 + RAG 1.5.0

Install these existing release wheels in a fresh environment. This installs APEX
3.1.1, not the current 3.2.0 source; it does not satisfy ASON 0.3.0's
`axiom-apex>=3.2.0` requirement.

```bash
python -m venv .venv
source .venv/bin/activate
python -m pip install \
  "axiom-rag @ https://github.com/axiom-llc/axiom-rag/releases/download/v1.5.0/axiom_rag-1.5.0-py3-none-any.whl" \
  "axiom-apex @ https://github.com/axiom-llc/axiom-apex/releases/download/v3.1.1/axiom_apex-3.1.1-py3-none-any.whl"
python -m pip check
```

Supply **both** wheels in the same command: APEX requires `axiom-rag>=1.5.0`,
and the old PyPI RAG cannot satisfy that contract. RAG 1.5.0 is already published.

Both URLs above target published release assets.
See [checksum verification and the future 3.2.0 release gates](../RELEASE.md). Third-party dependencies
may still be downloaded from the public Python index; no AXIOM PyPI account is needed.

### Current source: APEX 3.2.0

For the current source and ASON 0.3.0 integration, run from this checkout:

```bash
python -m venv .venv
source .venv/bin/activate
python -m pip install ../axiom-rag -e '.[dev]'
```

Check out matching RAG 1.5.0 source alongside APEX. Install RAG as a regular
package so RSI candidates do not depend on access to its source checkout.
Set `GEMINI_API_KEY` only for provider work, or select configured local Ollama.

## Container

Set both service credentials before exposing the execution API:

```bash
export GEMINI_API_KEY='...'
export APEX_API_KEY='replace-with-a-secret'
docker compose up --build
```

Set `LLM_PROVIDER=ollama` instead of `GEMINI_API_KEY` when the container can reach the configured Ollama endpoint. Require `APEX_API_KEY` for the Compose deployment because it binds port 8080 beyond loopback.

Persist APEX memory and history state in the `apex_data` volume. Deploy the trusted policy application separately and point it at the APEX HTTP API; prevent callers from bypassing that application.

