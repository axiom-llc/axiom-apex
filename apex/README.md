# APEX (Agentic Process Executor)

The **APEX** package is the plan-deterministic, policy-enforced execution engine of the Axiom LLC stack. It translates natural language intents into schema-validated, step-by-step plans and executes them inside bounded, audit-logged runtimes.

---

## 1. Operational Theory: Plan-Deterministic Execution

Traditional agent frameworks suffer from state explosion and unpredictable tool-invocation sequences because they re-evaluate the model at each execution step. 

APEX operates on the principle of **Plan-Deterministic Execution**:
1.  **Intent Generation**: The `planner.py` compiles the task prompt into a fully structured, declarative JSON `Plan` schema.
2.  **Policy Validation**: The `validator.py` evaluates the `Plan` against the active security profile (e.g., blocklists, step limits, blast-radius restrictions) *before* any tool is invoked.
3.  **Deterministic Transitions**: The `loop.py` steps through the validated plan sequentially. The tool sequence remains fully deterministic, recording results to an immutable SQLite transaction log at `~/.apex/runs.db`.

---

## 2. Submodule Overview

*   **`core/`** — Core execution logic, state managers, validation policies, and embedded search functions.
*   **`benchmarks/`** — Automated testing harnesses, adversarial suites, and codegen scenarios.
*   **`examples/`** — Deployable visual dashboards, telephony call servers, and multi-agent scripts.
*   **`tests/`** — Standard regression verification suites and mock datasets.
*   **`config.py`** — Handles configuration resolution and validation.
*   **`history.py`** — Database interface managing structured execution states.
*   **`llm.py` & `providers.py`** — Unified abstraction managing API calls (Gemini / Ollama).
*   **`mcp.py`** — Seamless Model Context Protocol (MCP) integrations.
*   **`server.py`** — Production Flask REST API hosting endpoints for execution and search.
*   **`templates.json`** — Consolidated dictionary of safety-policy profile boundaries.

---

## 3. Command-Line Execution Mechanics

The APEX CLI supports several flags to control the compiler's behavior:

*   **`--interactive`, `-i`** — Starts an interactive session loop.
*   **`--dry-run`** — Generates and displays the JSON plan without invoking any side-effect tools.
*   **`--trace`** — Streams step-by-step execution results to `stderr` in real-time.
*   **`--full-trace`** — Writes comprehensive JSONL structured events to file or stderr.
*   **`--paranoid`** — Audits the plan with a deterministic static prefilter and an LLM auditor before execution.

```bash
# Compile and run a dry-run to view the execution structure
apex "write system memory stats to ~/memory_report.txt" --dry-run
```

---

## 4. REST API Server (`apex serve`)

Run the threaded=False Flask server to expose programmatic task execution endpoints:
```bash
apex serve --host 127.0.0.1 --port 8080
```

### Key Endpoint Routings:
*   `POST /run` — Submit raw tasks. Accepts JSON `{"task": "..."}`. Returns `run_id`, execution status, step logs, and output.
*   `GET /runs` — Lists the last 20 active run logs.
*   `POST /replay` — Re-execute a run ID in `simulate`, `dry`, or `live` mode.

Set `APEX_API_KEY` to enforce validation headers:
```bash
export APEX_API_KEY=your-api-key
```
Requests must include the `X-Apex-Key` header.

---

## 5. Benchmark-Driven Self-Optimization (BDSO)

The system contains an automated self-optimization harness managed through `bench.py` and `rsi.py`. It evaluates performance based on a normalized fitness score:

$$\text{apex\_score} = \text{pass\_rate} \times \text{speed\_factor} \times \text{token\_efficiency}$$

To execute a self-improvement cycle:
```bash
python -m apex.bench --rsi --cycles 3 --budget-tokens 50000
```
This routine runs the benchmark, generates candidate patches via LLM, scores them on separate `rsi/cycle-N` branches, and prompts for human merge approval once an improvement is validated.

---

## 6. Custom Tool Extension

To add custom tools to the APEX runtime:

1.  **Define Tool in `core/tools.py`**:
    ```python
    CUSTOM_GET = Tool(
        name="custom_get",
        input_spec={"url": str},
        output_spec={"response": str},
        effect=lambda args: {"response": requests.get(args["url"]).text}
    )
    ```
2.  **Register in `__main__.py`**: Append `"custom_get": CUSTOM_GET` to the runtime `registry` dictionary.
3.  **Document in `prompt.txt`**: Add the signature to the prompt file so the planner can utilize it:
    `- custom_get: Perform an HTTP GET. args: {url: str}. returns: {response: str}`
