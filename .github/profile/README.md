# Axiom LLC — AI & Automation Systems

Engineers plan-deterministic AI Operating System layers over probabilistic language models.

Natural language → structured intent → schema-validated plans → bounded, inspectable runtimes.

All modules, research papers, compliance frameworks, and deployment blueprints are unified inside a single cohesive repository.

---

## 1. Unified Stack Topology

Axiom LLC organizes its entire software capability inside a single monorepo to eliminate distributed state drift, minimize maintenance overhead, and guarantee atomic dependency resolution:

```
Language Model (Planner)
        ↓
Structured JSON Intent
        ↓
Schema & Policy Boundary (apex/core/validator.py)
        ↓
Deterministic Execution Kernel (apex/core/loop.py)
        ↓
Tool Isolation & Callback Layer (apex/core/tools.py)
        ↓
Embedded Retrieval Engine (apex/core/rag.py)
        ↓
Applied Deployments & Blueprints (apex/examples/)
        ↓
Public Web Registry (docs/web/)
```

---

## 2. Repository Architecture Overview

Our complete software stack and publication record are packaged within **[`axiom`](https://github.com/axiom-llc/axiom)**:

| Folder Path | Operational Layer | Functional Purpose & Scope |
|---|---|---|
| **[`apex/core/`](https://github.com/axiom-llc/axiom/tree/main/apex/core)** | Execution Kernel | Functional run loops, SQLite-backed state/trace transitions, and schema-validated plan generation. |
| **[`apex/policy/`](https://github.com/axiom-llc/axiom/tree/main/apex/core)** | Safety &amp; Contracts | Pre-execution safety constraints: step-count limits, blocked tools, allowed-tool lists, and execution rollback mechanisms. |
| **[`apex/rag/`](https://github.com/axiom-llc/axiom/tree/main/apex/rag)** | Knowledge Boundary | In-process document chunking, semantic similarity retrieval filters, and grounded generation. |
| **[`apex/examples/`](https://github.com/axiom-llc/axiom/tree/main/apex/examples)** | Deployment Surface | Containerized voice agents (Twilio) and full-stack real-time data ingestion dashboards. |
| **[`docs/research/`](https://github.com/axiom-llc/axiom/tree/main/docs/research)** | Research Surface | Academic and systems publications focusing on deterministic safety, loop taxonomies, and computational self-reference. |
| **[`docs/web/`](https://github.com/axiom-llc/axiom/tree/main/docs/web)** | Public Registry | Organization website, portfolio, and architectural taxonomy documentation. |

---

## 3. Core Architectural Doctrines

All systems in this monorepo strictly comply with these tenets:
*   **Plan-Deterministic Invariance**: Identical verified plans strictly guarantee identical tool-call and callback sequences.
*   **Hard Boundaries**: All processes are capped at 32 max steps, 300s runtime limits, and isolated process memory.
*   **Safety Isolation**: Absolute blocklist enforcement (such as shell blocks) and sandbox blast-radius restrictions checked at the API boundary.

---

## 4. Consultancy Operations

Axiom LLC provides dedicated systems advisory and implementation services:
*   Deterministic runtime layout design
*   Secure agent policy and rollback integration
*   Context-grounded knowledge boundaries (RAG)
*   High-throughput tool calling pipelines
*   Client demonstration and containerized cloud deployment setup

**axiom.co@proton.me · [axiom-llc.github.io](https://axiom-llc.github.io)**
