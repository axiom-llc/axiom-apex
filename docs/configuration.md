# APEX configuration

[← Project overview](../README.md) · Commands below run from the repository root.

## Configure

| Variable               | Default                  | Purpose                                                                                                                   |
| ---------------------- | ------------------------ | ------------------------------------------------------------------------------------------------------------------------- |
| `LLM_PROVIDER`         | `gemini`                 | Select `gemini` or `ollama`.                                                                                              |
| `GEMINI_API_KEY`       | unset                    | Authenticate Gemini. Require it when `LLM_PROVIDER=gemini` and for local provider/evaluator operations; HTTP RAG uses server credentials.               |
| `GEMINI_MODEL`         | `gemini-3.8-flash`       | Select the Gemini planning and safety-audit model.                                                                        |
| `OLLAMA_BASE_URL`      | `http://localhost:11434` | Select the Ollama API endpoint.                                                                                           |
| `OLLAMA_MODEL`         | `llama3`                 | Select the Ollama model.                                                                                                  |
| `APEX_API_KEY`         | unset                    | Require `X-Apex-Key` for all HTTP routes except `/health` when set. Require it before binding the server beyond loopback. |
| `APEX_DB_PATH`         | `~/.apex/memory.db`      | Store key-value memory and swarm bookkeeping.                                                                             |
| `APEX_HISTORY_DB_PATH` | `~/.apex/runs.db`        | Store run plans, metrics, and tool events.                                                                                |
| `APEX_MCP_SERVERS`     | `[]`                     | Load MCP servers from a JSON array of `{"name", "url", "headers"?}` objects.                                              |
| `RAG_BASE_URL`         | required for storage; legacy tool defaults to `http://localhost:8000` | Select the RAG service.                                                         |
| `RAG_API_TOKEN`        | unset                    | Authenticate the hosted RAG service.                                                                                      |
| `RAG_CHROMA_PATH`      | `~/.rag/chroma`          | Select the canonical mapped root; HTTP adapters never open it.                                                                                   |
| `RAG_COLLECTION`       | `documents-gemini-embedding-2` | Select the authorized HTTP namespace.                                                                                     |
| `RAG_CHUNK_SIZE`       | `512`                    | Set words per chunk.                                                                                                      |
| `RAG_CHUNK_OVERLAP`    | `64`                     | Set overlapping words between chunks.                                                                                     |
| `RAG_TOP_K`            | `5`                      | Set retrieved chunk count.                                                                                                |
| `RAG_SCORE_THRESHOLD`  | `0.4`                    | Filter retrieval results by cosine-similarity score.                                                                      |
| `RAG_EMBEDDING_MODEL`  | `gemini-embedding-2`     | Select the Gemini embedding model.                                                                                        |
| `RAG_GENERATION_MODEL` | `gemini-3.5-flash-lite`  | Select the grounded RAG generation model.                                                                                 |

Reject unsupported `LLM_PROVIDER` values during startup. Validate RAG chunk sizes, overlap, retrieval count, score threshold, and collection name before use.

