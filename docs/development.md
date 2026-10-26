# APEX development

[← Project overview](../README.md) · Commands below run from the repository root.

## Run

```bash
apex "write 'hello world' to /tmp/out.txt and read it back"
apex --dry-run "write hello to /tmp/out.txt"
apex --audit "..."
apex --trace "..."
apex --full-trace --trace-path /tmp/trace.jsonl "..."
apex --interactive
apex --version
```

Use the subcommands:

```bash
apex history [-n 20]
apex stats
apex export --format jsonl|csv [--since ISO] [--fields a,b,c] [--events] [-o path]
apex replay <run_id> --mode simulate|dry|live [--diff] [--no-write]
apex serve [--host 127.0.0.1] [--port 8080]
apex swarm --tasks tasks.json [--workers 4] [--human-loop] [--trace-path PATH]
apex rsi [--cycles 3] [--budget-tokens 50000] [--tasks PATH] [--mock-bench]
```

Run the task benchmark:

```bash
python -m apex.bench --tasks benchmarks/tasks.json --mock
python -m apex.bench --tasks benchmarks/tasks.json
```

Compute `apex_score = pass_rate × speed_factor × token_efficiency`. Keep each factor in the inclusive range `0.01..1.0`, except `pass_rate`, which may be `0.0`. Benchmark JSON also records a secret-free `apex/execution-profile-v1` object and SHA-256 `config_digest` binding the resolved provider, model, database path, and runtime flags used by the benchmark process. Provider/model selection is resolved once at startup and passed explicitly to planning and audit calls rather than re-read from the environment.

## Architecture

Keep implementation modules under `apex/core/`. Preserve the top-level compatibility shims for established import paths.

```text
apex/
├── __main__.py         CLI and subcommand dispatch
├── config.py           runtime configuration
├── providers.py        Gemini/Ollama provider adapters
├── history.py          SQLite run/event history
├── export.py           history export
├── replay.py           recorded-plan replay
├── rsi.py              gated recursive-improvement experiment
├── bench.py            task benchmark harness
├── server.py           Flask HTTP API
├── mcp.py              MCP Streamable HTTP adapter
├── prompt.txt          plan-generation system prompt
└── core/
    ├── types.py        immutable plan/result/event/tool types
    ├── state.py        immutable runtime state
    ├── planner.py      prompt rendering and plan validation
    ├── loop.py         bounded execution loop
    ├── tools.py        built-in tools
    ├── toolloader.py   complete runtime registry construction
    ├── memory_store.py SQLite-backed memory tools
    ├── safety.py       plan audit
    ├── swarm.py        subprocess task dispatch
    ├── trace.py        JSONL trace writer
    └── rag/            HTTP RAG adapters and local provider exports
```

Import RAG modules through `apex.core.rag`; do not depend on a synthetic top-level `rag` package.

## Test

Run syntax validation:

```bash
python -m compileall -q apex benchmarks tests
```

Run offline unit tests without a Gemini API key:

```bash
python -m pytest tests/ -m 'not integration' -q
```

Run integration tests with the selected live provider configured:

```bash
python -m pytest tests/ -q
```

Run mock benchmarks without external model access:

```bash
python -m apex.bench --mock
python benchmarks/parallel_codegen.py --mock
```

## Ecosystem

* Use `axiom-ason` for caller-supplied pre-execution policy through a trusted application; do not infer automatic rollback.
* Use `axiom-demos` for applied integration examples.
* Use `axiom-research` for formal writeups.
* Use `axiom-llc.github.io` for the project site.

© AXIOM LLC.

Custom tools default to one execution attempt. Set `retry_safe=True` only when repeating the effect after a timeout or partial failure is safe. Shell, filesystem writes, memory writes, and MCP tools are not retried by default.

### Provider boundary checks

Make one generation attempt per provider call. Gemini uses a 60-second HTTP
timeout; Ollama uses 300 seconds. Return a generic provider failure without
recording upstream exception bodies, credentials, or prompt text. Retry explicitly
only after considering possible completed generation and quota usage.

Manual checks on 2026-09-11 exercised Gemini generation and invalid-model failure,
plus canonical RAG generation with `gemini-3.5-flash-lite`. The local Ollama server
accepted an explicit `OLLAMA_MODEL=gemma3:1b`; its uninstalled default `llama3`
failed cleanly. Set `OLLAMA_MODEL` to an installed model before selecting Ollama.
Run the existing integration tests explicitly with configured credentials; keep
hosted CI offline.

