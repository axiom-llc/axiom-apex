# AXIOM LLC
## AI Operating System Architecture & Automation Consultancy

AXIOM LLC engineers deterministic AI Operating System layers over probabilistic language models.

Natural language becomes structured intent. Structured intent becomes schema-validated plans. Plans execute inside bounded, inspectable runtimes.

All code, safety policies, retrieval models, research publications, and deployment surfaces are unified inside a single cohesive repository.

---

## The Unified Stack

Our complete core capabilities are packaged within the single primary repository: **[`axiom`](https://github.com/axiom-llc/axiom)**.

| Module | Layer | Structural Component & Capabilities |
|---|---|---|
| **[`apex/core/`](https://github.com/axiom-llc/axiom/tree/main/apex/core)** | Execution Kernel | Pure-functional state loop running schema-validated plan transitions. |
| **[`apex/policy/`](https://github.com/axiom-llc/axiom/tree/main/apex/core)** | Safety &amp; Contracts | Pre-execution safety constraints: step-count limits, blocked tools, allowed-tool lists, and execution rollback mechanisms. |
| **[`apex/rag/`](https://github.com/axiom-llc/axiom/tree/main/apex/rag)** | Knowledge Boundary | In-process document chunking, semantic similarity retrieval filters, and grounded generation. |
| **[`apex/examples/`](https://github.com/axiom-llc/axiom/tree/main/apex/examples)** | Deployment Surface | Containerized voice agents (Twilio) and full-stack real-time data ingestion dashboards. |
| **[`docs/research/`](https://github.com/axiom-llc/axiom/tree/main/docs/research)** | Research Surface | Academic and systems publications focusing on deterministic safety, loop taxonomies, and computational self-reference. |
| **[`docs/web/`](https://github.com/axiom-llc/axiom/tree/main/docs/web)** | Public Registry | Organization website, portfolio, and architectural taxonomy documentation. |

---

## Architectural Doctrine

All components within this unified boundary strictly enforce the following system invariants:
*   **Schema-Validated Plan Boundaries**: Every action sequence is pre-validated against Pydantic schemas before invocation.
*   **Deterministic Execution Kernels**: Identical verified plans strictly produce identical tool execution paths.
*   **Explicit State Transition Models**: Zero hidden mutable state; transitions are purely functional and SQLite-logged.
*   **Bounded Runtimes**: Structural caps on execution steps (max=32), total execution time (300s limit), and isolated process memory.
*   **Process-Isolated Side Effects**: Local execution domains and blast-radius constraints verified at the API boundary.
*   **Inspectable Execution Traces**: Detailed, real-time structured JSONL logs written for auditability.
*   **Minimal Dependency Surfaces**: Designed around minimal package footprint and lightweight system adapters.

---

## Contact

*   **Company**: `axiom.co@proton.me`
*   **Development**: `axiom.de@proton.me`
*   **Web Surface**: [`axiom-llc.github.io`](https://axiom-llc.github.io)
