# APEX integrations

[← Project overview](../README.md) · Commands below run from the repository root.

## HTTP API

Start a loopback server:

```bash
apex serve --host 127.0.0.1 --port 8080
```

Set an API key before binding beyond loopback:

```bash
export APEX_API_KEY='replace-with-a-secret'
apex serve --host 0.0.0.0 --port 8080
```

Refuse an unauthenticated non-loopback bind. Run the Flask process single-threaded because tool timeouts use `signal.alarm`, which requires main-thread execution.

| Route        | Method | Auth                         | Purpose                                                                           |
| ------------ | ------ | ---------------------------- | --------------------------------------------------------------------------------- |
| `/health`    | GET    | none                         | Return status and version.                                                        |
| `/run`       | POST   | `X-Apex-Key` when configured | Execute `{"task": "..."}` or an authorization-unbound exact `{"plan": {...}}`; return the run ID and validated plan. |
| `/authorized-run` | POST | same | Execute an exact plan only after atomically binding validated authorization metadata to its plan digest. |
| `/runs`      | GET    | same                         | Return recent runs with `?n=20`.                                                  |
| `/runs/<id>` | GET    | same                         | Return one run and its events.                                                    |
| `/replay`    | POST   | same                         | Replay with `simulate`, `dry`, or `live`.                                         |
| `/export`    | GET    | same                         | Export history as JSONL or CSV.                                                   |

## MCP

Configure MCP 2026-07-28 Streamable HTTP endpoints with `APEX_MCP_SERVERS`:

```bash
export APEX_MCP_SERVERS='[
  {"name":"local","url":"http://127.0.0.1:9000/mcp"}
]'
```

Add static request headers only when the server requires them:

```json
[
  {
    "name": "remote",
    "url": "https://example.invalid/mcp",
    "headers": {"Authorization": "Bearer token"}
  }
]
```

Send JSON-RPC `tools/list` and `tools/call` requests to each configured endpoint. Declare protocol version `2026-07-28` per request, include the required per-request MCP metadata, and emit `Mcp-Method`, `Mcp-Name`, and declared `Mcp-Param-*` routing headers where required.

Namespace loaded tools as `mcp__<server>__<tool>`. Skip malformed server definitions and unsupported tool schemas instead of inventing behavior. Reject MCP multi-round-trip input requests and Tasks-extension handles because APEX currently exposes only synchronous tool effects.

## RAG

`apex.core.rag.pipeline` and `apex.core.rag.store` use `rag.http_client.Client`
through the shared `rag.remote` adapters (requires matching RAG 1.5.0).
Set `RAG_BASE_URL=http://127.0.0.1:8000` explicitly for host-local storage calls.
There is no storage-client URL fallback. Only canonical `~/.rag/chroma`, namespace
`documents-gemini-embedding-2` and space `google-gemini / gemini-embedding-2 /
3072 / schema 1` are mapped. Other roots/namespaces/spaces fail before dispatch.
This host mapping does not configure Docker/infra connectivity.

File reads and ordered directory results stay local; text ingestion/query runs
on the server using its own `GEMINI_API_KEY`. Callers do not need or forward that
credential. Raw replacement/retrieval, delete and inspection use versioned HTTP.
Owner handles `_get_client` and `_get_collection` are no longer exposed; remote
create returns acknowledgement. Errors are explicit `RemoteError`, with no retry,
redirect, local fallback or client recovery. Unknown outcome never permits replay.

Preserve caller settings and APEX's `gemini-3.5-flash-lite` generation default;
RAG/CLI defaults to `gemini-2.5-flash`. Server policy permits both. Loopback needs
no bearer token; `RAG_API_TOKEN` may be sent when configured. Non-loopback server
authentication requirements remain intact.

`rag_multi_query` is unchanged: it uses legacy `POST /query`, its existing
`RAG_BASE_URL` default and server generation settings. Standalone embedder/generator
exports remain local. The evaluator intentionally imports local `rag.store` and
retains `documents`, local embedding and existing retrieval settings. It cannot
open the same root concurrently with its server owner; no evaluator migration or
namespace grant is implied.

Re-embed every existing collection after changing `RAG_EMBEDDING_MODEL`. Do not mix vectors produced by `gemini-embedding-2` with vectors from `gemini-embedding-001`, `text-embedding-004`, or any other embedding space.

Re-ingest a document to replace all of its previous chunks. Use directory-relative document IDs during recursive directory ingestion so files with identical basenames in different directories remain distinct. Preserve deterministic result ordering even when embedding files concurrently.

Evaluate retrieval quality with:

```bash
python benchmarks/eval_rag.py --dataset benchmarks/eval_rag_dataset.json
```


### Exact plan submission

`POST /run` accepts exactly one of `{"task": "..."}` or `{"plan": {...}}`.
Task requests use the planner as before. Plan requests use the same registry/schema
validation and existing execution kernel, without an LLM planning call. Invalid
plans return 400 before any tool runs. A plan requires a non-empty `goal`, typed
`steps`, and a final halt; the 32-step ceiling includes that halt. Authentication
and response fields are identical for both request forms. ASON 0.2+ uses this
interface to preserve its pre-execution policy decisions.

The `apex.core.rag` imports delegate to the canonical `axiom-rag>=1.5.0`
implementation. APEX retains its existing model defaults through its config
adapter. Retrieval changes and regressions belong in `axiom-rag`; both packages
use the same chunking, embedding, storage, and ingestion functions.

