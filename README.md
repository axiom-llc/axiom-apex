# AXIOM Apex

## Enterprise-Grade Parallel Swarm Orchestrator & Deterministic Execution Kernel

![Version](https://img.shields.io/badge/version-3.0.1-blue)
![Build](https://img.shields.io/badge/tests-134%20%2F%20134%20passed-success)
![Security](https://img.shields.io/badge/security-paranoid%20sandbox-red)
![Architecture](https://img.shields.io/badge/architecture-plan--deterministic-cyan)

AXIOM Apex is the production-grade execution kernel for the AXIOM LLC ecosystem. It provides a stateless, deterministic, and highly parallelized runtime designed to enforce absolute execution safety over probabilistic language models. By compiling natural language intents into schema-validated, declarative execution contracts, Apex ensures that identical inputs yield strictly reproducible, bounded, and auditable tool sequences.

---

## 1. System Architecture & The 8-Layer Stack

The AXIOM Apex architecture separates probabilistic planning from deterministic execution using a decoupled, 8-layer execution model.

```
       [ USER DIRECTIVE / NATURAL LANGUAGE INTENT ]
                           │
                           ▼
  Layer 1.  [ Language Model Planner ] ────────────► apex/llm.py (Generates raw plan)
                           │
                           ▼
  Layer 2.  [ Structured JSON Intent ] ────────────► apex/core/schema.py (Validates Pydantic schema)
                           │
                           ▼
  Layer 3.  [ Schema & Policy Boundary ] ──────────► apex/core/validator.py (Enforces blast-radius & blocks)
                           │
                           ▼
  Layer 4.  [ Deterministic Execution Kernel ] ────► apex/core/loop.py (Pure state transitions; max_steps=32)
                           │
                           ▼
  Layer 5.  [ Tool Isolation & Callback Layer ] ───► apex/core/tools.py (Process-isolated sandboxes)
                           │
                           ▼
  Layer 6.  [ Embedded Retrieval Engine ] ─────────► apex/core/rag.py (In-process vector context query)
                           │
                           ▼
  Layer 7.  [ Deployment Blueprints ] ─────────────► apex/templates.json (Instant specialized runtimes)
                           │
                           ▼
  Layer 8.  [ Public Web Registry ] ───────────────► axiom-llc.github.io (Continuous deployment portal)
```

---

## 2. Core Namespace Layout

The primary `apex` package houses the plan-deterministic execution engine, structured policy validation boundaries, and core resource connectors. The repository isolates the system’s execution library within the `apex/` subdirectory to maintain a clean packaging target.

### Directory Structure

```text
apex/
├── core/
│   ├── api_clients.py
│   ├── __init__.py
│   ├── loop.py
│   ├── planner.py
│   ├── rag.py
│   ├── rollback.py
│   ├── schema.py
│   ├── state.py
│   ├── swarm.py
│   ├── tools.py
│   ├── trace.py
│   ├── types.py
│   └── validator.py
├── config.py
├── history.py
├── __init__.py
├── llm.py
├── __main__.py
├── mcp.py
├── memory.py
├── paranoid.py
├── prompt.txt
├── providers.py
├── server.py
├── templates.json
├── templates.py
├── toolloader.py
└── tools.py
```

### Namespace Module Directory

<details>
<summary>Click to expand Root-Level Core Namespace Modules</summary>

| File Path | Purpose | Responsibilities | Core Dependencies | Integration Points | Operational Role |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `apex/__init__.py` | Package Initialization | Exposes central library APIs, configures workspace metadata, and sets shortcut bindings. | `apex/core/loop.py`, `apex/core/schema.py` | Import target for external consumers and automated test runners. | Packages the overall `apex` library namespace. |
| `apex/__main__.py` | CLI Entrypoint | Parses shell commands, manages CLI flag propagation, and dispatches tasks to the run loop. | `apex/config.py`, `apex/core/loop.py` | Bound to the global console execution script in `pyproject.toml`. | User-facing command line execution and service dispatch. |
| `apex/config.py` | Environment Settings | Loads and parses operational environment variables, directory default paths, and API keys. | `os`, `sys`, `pydantic` | Utilized by `providers.py`, `server.py`, and core modules to establish runtime parameters. | System initialization and resource configurations. |
| `apex/history.py` | SQL Persistence | Connects to SQLite (`runs.db`), logging task descriptions, metadata, and token consumption. | `sqlite3`, `json`, `apex/config.py` | Ingests trace packets emitted by `apex/core/trace.py` and feeds `server.py` queries. | Audit-trail preservation and execution telemetry history. |
| `apex/llm.py` | LLM Orchestrator | Translates planner intent payloads into model calls and injects system instructions. | `apex/providers.py`, `apex/prompt.txt` | Invoked directly by `apex/core/planner.py` to draft step-by-step candidate execution plans. | Pre-execution plan contract draft generator. |
| `apex/mcp.py` | Protocol Adapter | Standardizes tool bindings and the core execution loop under the Model Context Protocol. | Protocol serializers, `apex/core/tools.py` | Interfaces with third-party MCP-compliant development IDEs and external agent routers. | Standardized machine-to-machine context adapter. |
| `apex/memory.py` | Contextual Scratchpad | Manages an ephemeral, in-memory key-value dictionary during execution loops. | `json`, `apex/config.py` | Registered in the default tool catalog; exposed to the execution loop for variable storage. | Runtime scratchpad variable memory. |
| `apex/paranoid.py` | Security Guardrail | Enforces code-level lockouts, environment sanity checks, and monitors filesystem modifications. | `re`, `sys` | Wraps the primary execution loop; excluded from any optimization target lists. | Sandbox safety gate and invariant policy auditor. |
| `apex/prompt.txt` | Planner Directives | Instructs the LLM on generating plans conforming to system schemas. | None | Loaded dynamically by `apex/llm.py` and appended to prompt payloads. | Invariant system-level prompt guidelines. |
| `apex/providers.py` | API Shims | Houses concrete client implementations and request adaptors for Gemini and local Ollama APIs. | `google-genai`, `requests` | Standardizes outbound requests made by `apex/llm.py`. | Outbound provider abstraction layer. |
| `apex/server.py` | REST API Daemon | Runs the Flask microservice, manages authentication, and dispatches JSON payloads. | `flask`, `apex/core/loop.py` | Listens on port `8080` for client requests; runs single-threaded to preserve SIGALRM signals. | Production network interface daemon. |
| `apex/templates.json` | Blueprint Database | Acts as the structural registry mapping automated verticals (Solo Agency, RCM) to setup parameters. | None | Read by `apex/templates.py` to spawn runtime instances. | Declarative corporate blueprint database. |
| `apex/templates.py` | Blueprint Builder | Validates and instantiates dynamic business profiles from the template registry. | `json`, `pydantic`, `apex/templates.json` | Specialized by `apex/core/planner.py` to structure target execution environments. | Pre-planning setup and parameter injector. |
| `apex/toolloader.py` | Tool Autoloader | Scans filesystem directories and dynamically registers third-party execution tools. | `importlib`, `pkgutil` | Populates the tool catalog held within `apex/core/tools.py`. | Runtime capability extension manager. |
| `apex/tools.py` | Baseline Tools | Implements baseline system utilities (local file reads, file writes, HTTP GET operations). | Local filesystem, `pydantic` | Bound directly to the core tool catalog. | Default execution capabilities. |

</details>

<details>
<summary>Click to expand Core Submodule Namespace (apex/core/)</summary>

| File Path | Purpose | Responsibilities | Core Dependencies | Integration Points | Operational Role |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `apex/core/api_clients.py` | Network Clients | Manages low-level connection pools, client timeouts, and retries for external services. | `requests`, `urllib3` | Called by `apex/providers.py` to handle remote network requests. | Outbound transport security and resilience. |
| `apex/core/__init__.py` | Submodule Init | Exposes the run loop, planners, swarms, and safety validators to the parent package namespace. | Sibling modules | Unifies subpackage-level core execution imports. | Internal subpackage boundary. |
| `apex/core/loop.py` | Execution Kernel | Coordinates state transitions, executes planned actions, and handles transactional recoveries. | `apex/core/state.py`, `apex/core/tools.py` | Called by `apex/server.py` and `apex/__main__.py` to process tasks. | Core transition engine and state machine. |
| `apex/core/planner.py` | Task Compiler | Processes natural language goals into a structured, step-by-step execution plan contract. | `apex/llm.py`, `apex/core/schema.py` | Called prior to execution to prepare the state transitions contract. | Pre-execution compilation stage. |
| `apex/core/rag.py` | Grounding Engine | Handles document chunking and queries the vector database (ChromaDB) for context validation. | `chromadb`, `pydantic` | Registered as a core tool; provides context injection to the planner. | In-process semantic context grounding. |
| `apex/core/rollback.py` | Transactional Rollback | Evaluates execution event logs and builds a reverse plan to undo side effects on failure. | `apex/core/schema.py` | Invoked automatically by `apex/core/loop.py` when an execution contract step fails. | Fault recovery and state cleanup engine. |
| `apex/core/schema.py` | Contract Definition | Defines and validates Pydantic models for plan structures, step sequences, and tool signatures. | `pydantic` | Imported by `planner.py`, `validator.py`, and `loop.py` to enforce code contracts. | Create-time and runtime model validation. |
| `apex/core/state.py` | State Tracker | Tracks variable values, records step outputs, and manages execution state transitions. | Sibling modules | Read and updated dynamically by `loop.py` during execution. | Thread-safe operational state storage. |
| `apex/core/swarm.py` | Swarm Coordinator | Deploys and manages multiple run loops in parallel across thread-safe pools. | `concurrent.futures`, `apex/core/loop.py` | Called by complex workflows to run asynchronous tasks. | Parallel and concurrent execution manager. |
| `apex/core/tools.py` | Tool Execution | Registers tool callbacks and enforces process containment during action execution. | `subprocess`, `sys` | Interfaces with the tool registrar to safeguard tool execution. | Process-isolated tool sandboxing. |
| `apex/core/trace.py` | Telemetry Collector | Formats and emits structured telemetry packets, trace logs, and execution times. | `json`, `datetime` | Feeds structured event logs into `apex/history.py` for SQLite persistence. | Telemetry and event logging. |
| `apex/core/types.py` | System Primitives | Houses global enums, types, and execution exit codes. | None | Core types imported universally by the submodule files. | Base type definitions. |
| `apex/core/validator.py` | Pre-Execution Guard | Validates plans against security rules (blast-radius and allowlists) before execution begins. | `re`, `apex/core/schema.py` | Evaluates the plan contract after generation but before execution is initiated by `loop.py`. | Pre-execution security gating. |

</details>

---

## 3. Configuration & Authentication Parameters

The system resolves configuration settings exclusively from the environment at startup. If configuration values do not validate, the engine halts execution before runtime setup occurs.

### Environment Variables Dictionary

| Environment Variable | Type | Default Value | Description |
| :--- | :--- | :--- | :--- |
| `GEMINI_API_KEY` | String | *Required (No default)* | Direct credentials for the upstream Google GenAI service. Crucial for execution plan generation. |
| `APEX_API_KEY` | String / Null | `None` | Authentication secret key for Flask microservices. If empty, the daemon serves without authentication. |
| `APEX_DB_PATH` | Path / String | `~/.apex/runs.db` | Target SQLite filepath for execution history logging, event audit registries, and run metrics. |
| `APEX_MCP_SERVERS` | JSON Array | `[]` | Parsed configurations representing connected Model Context Protocol servers. |

---

## 4. REST API & MCP Integration

AXIOM Apex exposes a low-latency, single-threaded Flask server daemon executing on port `8080`. Single-threading is strictly enforced (`threaded=False`) to prevent multi-threaded request dispatches from breaking Unix signal-level timers (`signal.alarm`).

### Rest HTTP API Specifications

```
                       [ REST API CLIENT / CLIENT PORTAL ]
                                       │
                                       ▼
                       [ Header check: X-Apex-Key? ]
                                       │
                   ┌───────────────────┴───────────────────┐
                   ▼                                       ▼
         [ Header matches? ]                     [ Header missing/invalid ]
                   │                                       │
                   ▼                                       ▼
         [ Process JSON Request ]                    [ 401 Unauthorized ]
                   │
         ┌─────────┴───────────────────────────────┐
         ▼                                         ▼
   [ POST /run ]                             [ POST /replay ]
   Body:                                     Body:
   - task: "Clean disk logs..."              - run_id: 1042
   - config: { paranoid: true }              - mode: "dry"
         │                                         │
         ▼                                         ▼
   [ Run loop execution ]                    [ Run loop execution ]
   Returns:                                  Returns:
   - exit_code: 0                            - exit_code: 0
   - status: "HALTED"                        - output: "Reconstructed..."
   - output: "Successfully cleaned..."
```

#### 1. Task Execution (`POST /run`)
*   **Authentication**: Optional. If `APEX_API_KEY` is set, requires `X-Apex-Key` header matching.
*   **Request JSON Schema**:
    ```json
    {
      "task": "Write current directory contents to /tmp/contents.txt and read it back",
      "config": {
        "trace": true,
        "dry_run": false,
        "full_trace": false,
        "paranoid": true
      }
    }
    ```
*   **Response JSON Schema**:
    ```json
    {
      "run_id": 1024,
      "plan": {
        "steps": [
          { "step": 1, "tool": "shell", "args": { "cmd": "ls" } },
          { "step": 2, "tool": "write_file", "args": { "path": "/tmp/contents.txt", "content": "..." } }
        ]
      },
      "exit_code": 0,
      "status": "HALTED",
      "output": "Successfully completed task execution",
      "token_count": 4210,
      "step_count": 2
    }
    ```

#### 2. Process Replay (`POST /replay`)
*   **Authentication**: Required if `APEX_API_KEY` is active.
*   **Request JSON Schema**:
    ```json
    {
      "run_id": 1024,
      "mode": "dry"
    }
    ```
    *Note: Valid replay modes are `simulate` (trace analysis without execution), `dry` (execute plan without side-effect commits), and `live` (full execution).*
*   **Response JSON Schema**:
    ```json
    {
      "run_id": 1024,
      "mode": "dry",
      "exit_code": 0,
      "output": "Replay simulation completed. Event count matches baseline."
    }
    ```

---

### Model Context Protocol (MCP) Client Setup

The core engine includes an MCP adapter (`apex/mcp.py`) that maps external protocol servers into native tool definitions. This allows AXIOM Apex to import tools from external servers seamlessly.

```
 [ AXIOM Apex Engine ]                                     [ External MCP Server ]
         │                                                            │
         │ 1. POST /tools/list ──────────────────────────────────────►│
         │◄─────────────────────────────────────── 2. JSON Tool List  │
         │ (Maps tools into namespaced schemas)                       │
         │                                                            │
         │ 3. Execute Swarm Loop (User action triggers tool)         │
         │                                                            │
         │ 4. POST /tools/call {"name": ..., "arguments": ...} ──────►│
         │◄─────────────────────────────────────── 5. JSON Response   │
```

#### Enforcing Protocol Schemas
1.  **Tool Discovery**: At server boot, AXIOM Apex connects to the registered servers via `POST /tools/list`, reading the JSON schemas of external tools and binding them under the unique namespace:
    ```text
    mcp__{server_name}__{raw_tool_name}
    ```
2.  **Execution Transport**: When the planning model selects a namespaced tool, `apex/mcp.py` formats a secure payload containing the arguments dictionary and dispatches it via:
    ```text
    POST {base_url}/tools/call
    ```
3.  **Error Handling**: If the returned payload has the boolean parameter `isError` set to true, the execution loop catches the event, raises a `RuntimeError`, and initiates the transactional rollback sequence.

---

## 5. Transactional Rollback Architecture

AXIOM Apex implements transactional rollback guarantees via `apex/core/rollback.py`. This ensures that when a multi-step plan encounters an execution failure, the system attempts to reverse its physical side effects automatically.

```
 [ STEP 1: Write File ] ──────────────────────────► (Succeeds)
 [ STEP 2: Write File ] ──────────────────────────► (Succeeds)
 [ STEP 3: Network POST ] ────────────────────────► (Fails: HTTP 500)
                                                          │
                                                          ▼
                                             [ ACTIVATE ROLLBACK AGENT ]
                                              Queries runs.db for events
                                                          │
                                                          ▼
                                              [ BUILD REVERSAL PLAN ]
                                              Step 2: write_file ──► delete_file
                                              Step 1: write_file ──► delete_file
                                                          │
                                                          ▼
                                              [ RECOVERY ENVELOPE ]
                                             Executes with strict safety:
                                             Policy(rollback_on_failure=False)
```

### Compensating Action Schema
The rollback generator queries the SQLite `events` database for the target execution ID in reverse order (`ORDER BY step DESC`). It evaluates the logged actions and maps them to their respective compensating operations:

```json
{
  "plan": {
    "steps": [
      {
        "step": 1,
        "tool": "delete_file",
        "args": {
          "path": "/tmp/interim_work.txt"
        }
      }
    ]
  },
  "policy": {
    "max_steps": 16,
    "allowed_tools": ["delete_file"],
    "blast_radius": "local",
    "rollback_on_failure": false
  }
}
```

### Safety Gating Over Rollbacks
To prevent recursive execution loops (i.e., a rollback plan failing and triggering another rollback), AXIOM Apex injects a strict safety policy into the recovery run contract:
```python
Policy(blast_radius="local", rollback_on_failure=False)
```
This restricts the rollback process to localized operations and disables secondary recovery, protecting system resources from infinite regression loops. If a non-reversible tool (such as `shell`) is encountered during compilation, the rollback engine halts and logs a warning requesting manual review:
```text
rollback: step 4 (shell): shell side-effects unresolvable — manual review required
```

---

## 6. Backwards Compatibility Bridge

To maintain 100% test compatibility across system restructures, AXIOM Apex implements a zero-impact **Backwards Compatibility Bridge** within its verification layer (`tests/conftest.py`). 

```
   [ Legacy Test Suite (Imports 'ason.*') ]
                      │
                      ▼
     [ Runtime Compatibility Interceptor ] ──► Dynamically injects matching
                      │                         modules into sys.modules
                      ▼
     [ Target Namespace Compatibility Map ]
     - ason          ──────────► apex/core/schema.py
     - ason.schema   ──────────► apex/core/schema.py
     - ason.validator ─────────► apex/core/validator.py
     - ason.rollback ──────────► apex/core/rollback.py
     - ason.executor ──────────► Custom compatibility runner
```

When Pytest boots, `conftest.py` dynamically intercepts system imports and maps historical references to the newly consolidated `apex.core` validation modules at runtime:

```python
import sys
import types
from apex.core import schema, validator, rollback

# Dynamically construct and bind the legacy 'ason' namespace to sys.modules
ason_mod = types.ModuleType("ason")
sys.modules["ason"] = ason_mod
sys.modules["ason.schema"] = schema
sys.modules["ason.validator"] = validator
sys.modules["ason.rollback"] = rollback
```

This ensures that historical execution suites, third-party integrations, and verification workflows continue to compile and validate with zero code changes required.

---

## 7. Context-Grounding Search Engine (RAG)

AXIOM Apex embeds an in-process semantic context grounding and retrieval engine within `apex/core/rag.py` to prevent hallucination cycles during planning.

### Word-Level Chunking Strategies
To maximize context window utilization, chunking boundaries are measured strictly in **words** instead of tokens. For typical English text, word count is approximately $0.75 \times$ token count, allowing a default $512$-word chunk to fit comfortably inside the context boundaries of Gemini's text-embedding models:

*   **Fixed-Size Strategy (`chunk_fixed`)**: Splits text on word boundaries to a configurable word ceiling (default `RAG_CHUNK_SIZE=512`), maintaining a sliding context overlap (default `RAG_CHUNK_OVERLAP=64`) to preserve continuity across boundaries.
*   **Sentence-Group Strategy (`chunk_sentences`)**: Evaluates sentence-ending punctuation using regular expression splits (`r"(?<=[.!?])\s+"`) and aggregates sentences into cohesive structural blocks up to the maximum word threshold.

### Asymmetric Embedding Transport
Retrieval operations utilize Gemini's `text-embedding-004` model. To maximize matching precision, RAG operations implement an asymmetric task type model:

*   **Document Indexing**: Document chunks are vectorized using `task_type="RETRIEVAL_DOCUMENT"`.
*   **Query Vectorization**: User queries are vectorized at search time using `task_type="RETRIEVAL_QUERY"`.

#### Distance Metric Conversions
ChromaDB collections are initialized using cosine distance metrics:
```python
_get_client(path).get_or_create_collection(
    name=config.collection_name,
    metadata={"hnsw:space": "cosine"}
)
```
At query time, the system converts ChromaDB's raw cosine distance into similarity scores, filtering out matches falling below the security threshold (default `RAG_SCORE_THRESHOLD=0.4`):
$$\text{Score} = 1.0 - \text{Cosine Distance}$$

---

## 8. Database Schema & Migration Guide

AXIOM Apex automatically initializes and manages its database tracking layer inside `apex/history.py`.

```
                [ SERVER DAEMON / RUN INITIATION ]
                                │
                                ▼
                   [ DB Connection check (_conn) ]
                   - Creates directory path ~/.apex/
                   - Connects to SQLite runs.db
                                │
                   ┌────────────┴────────────┐
                   ▼                         ▼
         [ Tables exist? ]          [ Tables missing? ]
                   │                         │
                   ▼                         ▼
          [ Proceed to run ]        [ Execute DDL Scripts ]
                                    - Create Table runs
                                    - Create Table events
```

The database structures are automatically created at boot time inside `~/.apex/runs.db` using the following schema layouts:

### SQLite Table Definitions

#### 1. Execution Runs Table (`runs`)
Tracks top-level metadata, tasks, generated plans, token counts, and execution speeds:

```sql
CREATE TABLE IF NOT EXISTS runs (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    task         TEXT    NOT NULL,
    plan_json    TEXT,
    exit_code    INTEGER,
    token_count  INTEGER,
    wall_seconds REAL,
    timestamp    TEXT    NOT NULL DEFAULT (datetime('now','utc'))
);
```

#### 2. Event Log Table (`events`)
Tracks granular action details, step orders, parameters, and tool return payloads:

```sql
CREATE TABLE IF NOT EXISTS events (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    run_id      INTEGER NOT NULL REFERENCES runs(id),
    step        INTEGER NOT NULL,
    tool        TEXT    NOT NULL,
    args_json   TEXT,
    result_json TEXT,
    timestamp   TEXT    NOT NULL DEFAULT (datetime('now','utc'))
);
```

---

## 9. RSI: Recursive Self-Improvement

AXIOM Apex integrates a **Benchmark-Driven Self-Optimization (BDSO)** loop, referred to as the RSI (Recursive Self-Improvement) architecture. Located in `bench.py` and dispatched from `apex/rsi.py`, this allows the system to autonomously optimize its own planning and execution heuristics.

```
                  [ START RSI CYCLE (apex rsi) ]
                                 │
                                 ▼
                     [ Generate Candidate Patches ]
                  Proposes N=3 patches to non-critical 
                       modules (loop.py, planner.py)
                                 │
                                 ▼
                    [ Process-Isolated Sandboxing ]
                   Executes each candidate in ephemeral, 
                        isolated subprocesses
                                 │
                                 ▼
                      [ Empirical Evaluation ]
                     Scores candidate fitness using:
                     apex_score = pass_rate × speed × efficiency
                                 │
                   ┌─────────────┴─────────────┐
                   ▼                           ▼
        [ Exceeds Baseline? ]        [ Underperforms? ]
                   │                           │
                   ▼                           ▼
         [ Autonomous Commit ]         [ Discard Patch ]
         Applies patch and updates     Terminates cycle; 
          active codebase state        preserves baseline
```

### The Fitness Function
RSI performance is mathematically evaluated against the `apex_score` composite index:

$$\text{Score} = \text{Pass Rate} \times \text{Speed Factor} \times \text{Token Efficiency}$$

Where:
*   **$\text{Pass Rate}$**: $\frac{\text{Passed Tasks}}{\text{Total Tasks}}$
*   **$\text{Speed Factor}$**: $\max\left(0.01, \ 1.0 - \frac{\text{Avg Duration Seconds} - 10.0}{200.0}\right)$
*   **$\text{Token Efficiency}$**: $\max\left(0.01, \ 1.0 - \frac{\text{Avg Tokens} - 1000.0}{50000.0}\right)$

### Invariant Security Boundary
The self-optimization engine's target file list is restricted to `{loop.py, planner.py, llm.py}`. The plan auditor (`paranoid.py`) is **permanently excluded** from self-optimization. This is a system-level architectural constraint that guarantees the system cannot optimize away or bypass its own safety validator.

---

## 10. Autonomous Business Unit Templates

The `templates.json` catalog acts as a "Commercial DNA" registry, allowing the AXIOM Apex planning engine to instantly specialize into various business verticals.

```json
{
  "solo_agency": {
    "name": "Solo Consulting Agency Lifecycle",
    "description": "Qualifies incoming leads, drafts scope proposals, logs billable hours, and tracks unpaid invoices",
    "required_data": ["~/agency/leads/", "~/agency/proposals/", "~/agency/projects/", "~/agency/invoices/"],
    "allowed_tools": ["read_file", "write_file", "send_email", "calculate_fees"],
    "blast_radius": "local"
  },
  "compliance_audit": {
    "name": "Regulatory Compliance & Security Audit",
    "description": "Performs nightly system security spot-checks and compiles framework audits (SOC 2, HIPAA, PCI-DSS)",
    "required_data": ["~/compliance/evidence/", "~/compliance/findings/", "~/compliance/reports/"],
    "allowed_tools": ["read_file", "write_file", "check_system_logs", "audit_firewall"],
    "blast_radius": "local"
  }
}
```

When a template is loaded via `templates.py`, the core loop imports the specified parameters, restricts available tools to the `allowed_tools` set, and configures the `blast_radius` safety policy of the pre-execution validator.

---

## 11. Security, Sandboxing & Concurrency Engineering

```
                      [ SUBMIT PLAN CONTRACT ]
                                 │
                                 ▼
                   [ Pre-Execution Policy Audit ]
                   - Schema contract validation
                   - Regex blocked command blocklist
                   - Blast-radius policy checks (none|local|network)
                                 │
                   ┌─────────────┴─────────────┐
                   ▼                           ▼
            [ Policy Pass ]             [ Policy Fail ]
                   │                           │
                   ▼                           ▼
        [ Launch Swarm Thread Pool ]   [ Reject Plan ]
         Asynchronous parallel task     Returns structured diagnostics;
         runners spawned in sandbox     aborts execution immediately
                   │
                   ▼
       [ Process-Isolated Action Execution ]
        - signal.alarm SIGALRM active
        - Timeout boundaries enforced
```

### Safety and Isolation Mechanisms
*   **Pre-Execution Audit**: Every plan is validated against Pydantic schemas and regular expression blocklists before a single tool is invoked.
*   **Blast-Radius Enforcement**: Tools are classified by impact (`none`, `local`, `network`). Policy hard-gates execution based on the environment's configured tolerance.
*   **SIGALRM Isolation**: Tool timeouts are enforced at the Unix signal level, preventing hung processes from exhausting system resources.
*   **Asynchronous Parallel Swarms**: `core/swarm.py` manages thread-safe worker pools, orchestrating high-concurrency loops without risk of variable pollution or race conditions.

---

## 12. Installation & Quickstart

### Prerequisites
*   **Python**: 3.11+ (Supported across modern slim-image deployments)
*   **LaTeX Engine** (Optional, for compiling academic publications): `tectonic` (installed via `sudo pacman -S tectonic` on Arch Linux)
*   **API Keys**: `GEMINI_API_KEY` (Gemini API access)

### Local Environment Setup
Register AXIOM Apex globally in editable mode to preserve immediate updates to the core package:

```bash
cd ~/c/axiom-llc/axiom-apex
pip install -e . --break-system-packages
```

### Minimal Working Example (CLI)
Execute a task directly from your terminal using AXIOM Apex's plan-deterministic engine:

```bash
apex run --task "write 'hello world' to /tmp/axiom-out.txt and verify its content" --paranoid
```

### Minimal Working Example (Python)
Define and run a plan contract programmatically:

```python
import json
from apex.core.loop import run
from apex.core.schema import Config, ToolRegistry

# 1. Define runtime configurations
config = Config(max_steps=10, blast_radius="local", paranoid_mode=True)
registry = ToolRegistry()

# 2. Define the declarative execution contract (The Plan)
task_plan = {
    "task": "Write and verify compliance signature",
    "steps": [
        {
            "step": 1,
            "tool": "write_file",
            "args": {"path": "/tmp/signature.txt", "content": "compliance-verified-2026"}
        },
        {
            "step": 2,
            "tool": "read_file",
            "args": {"path": "/tmp/signature.txt"}
        }
    ]
}

# 3. Submit contract to the deterministic run loop
state = run(task_plan, config, registry)
print(f"Execution Status: {state.status} | Trace: {json.dumps(state.history, indent=2)}")
```

### Running the API Daemon
Expose the execution kernel as a Flask microservice listening on port `8080`:

```bash
apex serve --paranoid
```

---

## 13. Containerized Orchestration (Docker)

AXIOM Apex is optimized to compile and deploy within lightweight Linux containers.

### Multi-Stage Container Composition (`Dockerfile`)
The package uses a streamlined, cached Python build stage exposing HTTP interface ports and tracking health checks:

```dockerfile
FROM python:3.12-slim
WORKDIR /app
COPY . .
RUN pip install --no-cache-dir -e ".[dev]"
EXPOSE 8080
HEALTHCHECK --interval=10s --timeout=3s --retries=5 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8080/health')"
CMD ["apex", "serve", "--host", "0.0.0.0", "--port", "8080"]
```

### Deployment (`docker-compose.yml`)
Binds port 8080, mounts volumes for tracking persistence, and injects API credentials:

```yaml
version: "3.8"
services:
  apex:
    build: .
    ports:
      - "8080:8080"
    environment:
      - GEMINI_API_KEY=${GEMINI_API_KEY}
      - APEX_API_KEY=${APEX_API_KEY}
    volumes:
      - ~/.apex:/root/.apex
```

---

## 14. Verification & Performance Benchmarking

AXIOM Apex maintains a 100% pass rate across 134 deterministic regression tests.

```bash
# Execute the full verification suite
pytest tests/
```

### Running Automated Benchmarks
AXIOM Apex contains a performance benchmark engine within `bench.py`. Execute the harness to run tasks defined inside `tasks.json`:

```bash
python3 bench.py
```

### Tasks Configuration Layout (`tasks.json`)
The performance suite evaluates processing latency, token efficiency, and correctness using a structured, reproducible config:

```json
[
  {
    "id": "write_file",
    "prompt": "write 'hello world' to /tmp/apex-bench-out.txt",
    "check": "hello",
    "check_file": "/tmp/apex-bench-out.txt"
  },
  {
    "id": "read_file",
    "prompt": "write 'readtest' to /tmp/apex-bench-read.txt then read it back and output the contents",
    "check": "readtest"
  }
]
```

---

## 15. Official Ecosystem

*   **AXIOM Apex (Core Engine)**: [github.com/axiom-llc/axiom-apex](https://github.com/axiom-llc/axiom-apex)
*   **AXIOM Demos (Blueprints)**: [github.com/axiom-llc/axiom-demos](https://github.com/axiom-llc/axiom-demos)
*   **AXIOM Research (Theory)**: [github.com/axiom-llc/axiom-research](https://github.com/axiom-llc/axiom-research)
*   **AXIOM Portal (Web)**: [axiom-llc.github.io](https://axiom-llc.github.io)

---
© 2026 AXIOM LLC. Built for deterministic autonomous execution.
