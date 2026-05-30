# APEX Package Core

This directory houses the core software engine, evaluation suites, industrial blueprints, and standard test libraries of the APEX runtime. 

---

## Directory Structure

*   `core/` — The deterministic execution kernel. Houses the functional run loop, safety validators, rollback protocols, internal tool integrations, and the in-process RAG pipeline.
*   `benchmarks/` — Performance testing scripts, dataset specifications, and execution scoring logs.
*   `examples/` — Vertical industry automation blueprints, interactive multi-agent scripts, and container definitions.
*   `tests/` — Component-specific regression testing suites, mock data, and boundary tests.
*   `config.py` — Fixed configuration data schema.
*   `history.py` — Database schema and interface for recording run events.
*   `llm.py` & `providers.py` — Model and platform abstractions (Gemini / Ollama).
*   `mcp.py` — Model Context Protocol (MCP) tool ingestion adapters.
*   `server.py` — Flask service exposing program-driven execution endpoints.
*   `templates.json` — Consolidated configuration safety policy profiles.

---

## Core Concepts & Modification Lanes

### 1. Extending the Tool Registry
To register custom functional capabilities:
1.  Define the `Tool` contract in `core/tools.py` with its `name`, input parameters, output parameters, and side-effect implementation lambda or function.
2.  Include the new tool in the CLI register located in `__main__.py`.
3.  Document the tool description, required schema arguments, and expected output parameters in `prompt.txt`.

### 2. Modifying Safety and Contracts
Before customizing pre-execution policies:
*   `core/validator.py` evaluates plans through a deterministic regex filter and an LLM plan audit.
*   `core/schema.py` defines the valid policy parameter boundaries (step count, tool blocklists, blast radius ceilings).
*   *Caution:* `core/validator.py` functions as the absolute safety boundary and is structurally locked from autonomous self-optimization (BDSO) cycles.

### 3. Executing the Local Optimizer (BDSO)
The Benchmark-Driven Self-Optimization suite operates via `bench.py`. It runs cycle testing against `benchmarks/tasks.json` to score changes and generate patches:
```bash
python -m apex.bench --rsi --cycles 2 --budget-tokens 30000
```

---

## Testing and Validation

Run the entire consolidated testing suite locally:
```bash
pytest tests/ -q
```
Ensure tests are evaluated on Python 3.11 and 3.12 prior to push requests.
