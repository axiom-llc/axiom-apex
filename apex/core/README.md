# APEX Core Execution Kernel

This directory houses the functional transition engine, schema parsing boundaries, and security validation gateways of the APEX runtime.

---

## 1. Engine Architecture & Module Topology

```
                  ┌──────────────────────────┐
                  │      CLI ENTRYPOINT      │
                  │    apex/__main__.py      │
                  └────────────┬─────────────┘
                               ▼
                  ┌──────────────────────────┐
                  │      PLAN GENERATOR      │
                  │    apex/core/planner.py  │
                  └────────────┬─────────────┘
                               ▼
                  ┌──────────────────────────┐
                  │     PARANOID AUDITOR     │
                  │   apex/core/validator.py │
                  └────────────┬─────────────┘
                               ▼ (Passed Security Checks)
                  ┌──────────────────────────┐
                  │  PURE EXECUTION KERNEL   │
                  │     apex/core/loop.py    │
                  └────────────┬─────────────┘
                               ├───────────────────┐
                               ▼ (System Tools)    ▼ (Parallel Swarms)
                  ┌────────────────────────┐  ┌───────────────────────┐
                  │     PROCESS TOOLS      │  │     SWARM ENGINE      │
                  │  shell, read/write,    │  │   apex/core/swarm.py  │
                  │  http_get, rag_query   │  │   (Subprocess Popen)  │
                  └────────────────────────┘  └───────────────────────┘
```

---

## 2. Core Submodules

### A. Pure Functional State Loop (`loop.py`)
APEX bypasses global states or implicit transitions by executing task processing as a pure mathematical function:
$$\text{run}(Task, Config, Registry) \to State$$
Every action (tool call, status shift, error tracking) generates an immutable copy of the state, maintaining a deterministic ledger.

### B. Two-Stage Validation Gateways (`validator.py`)
To make AI execution safe for local operating systems, APEX uses a hybrid validation gateway:
1.  **Static Regex Prefilter**: Instantly intercepts known destructive patterns (e.g., `rm -rf /`, `chmod 777`, pipe-to-shell installers) locally, bypassing the LLM.
2.  **LLM Paranoid Audit**: Converts the plan into JSON and requests a specialized security audit from `gemini-3.1-flash-lite`, returning a risk analysis before execution is authorized.

### C. Process-Isolated Swarms (`swarm.py`)
To run parallel tasks concurrently with true memory safety, the swarm engine avoids thread sharing. Instead, it spawns agents inside independent OS-level processes via `subprocess.Popen` running the APEX binary. Run states are tracked inside a local SQLite database (`~/.apex/memory.db`) for transaction auditability.

### D. Dynamic Delegator Shim (`rag.py`)
Includes a custom `types.ModuleType` subclass (`Delegator`) that dynamically links virtual packages (e.g., `rag.store`, `rag.pipeline`) back to the consolidated `apex.core.rag` module at runtime, maintaining backward compatibility with legacy API imports.
