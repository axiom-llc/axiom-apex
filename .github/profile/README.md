---

## The Monorepo: `axiom`

Our complete operating capability is packaged within [github.com/axiom-llc/axiom](https://github.com/axiom-llc/axiom) [2]:

| Module Directory | Operational Layer | Purpose & Capabilities |
|---|---|---|
| [`apex/core/`](https://github.com/axiom-llc/axiom/tree/main/apex/core) | Execution Kernel | Functional run loops, SQLite-backed state/trace transitions, and schema-validated plan generation [2]. |
| [`apex/policy/`](https://github.com/axiom-llc/axiom/tree/main/apex/policy) | Execution Contracts | Pre-execution safety boundaries governing step caps, blocked tools, allowed-tool lists, and execution rollback mechanisms [2]. |
| [`apex/rag/`](https://github.com/axiom-llc/axiom/tree/main/apex/rag) | Knowledge Boundary | Embedded, in-process vector store adapters, semantic similarity filters, context-grounded response pipeline [2]. |
| [`apex/examples/`](https://github.com/axiom-llc/axiom/tree/main/apex/examples) | Deployment Surface | Multi-agent swarms, Twilio voice agents, real-time logistics dashboard engine [2]. |
| [`docs/research/`](https://github.com/axiom-llc/axiom/tree/main/docs/research) | Independent Research | Peer-reviewed and preprint publications on deterministic safety, loop taxonomies, and computational self-reference [2]. |
| [`docs/web/`](https://github.com/axiom-llc/axiom/tree/main/docs/web) | Public Registry | Architectural portfolio, taxonomy catalog, and organizational contact web page [2]. |

---

## Global System Invariants

All components within this unified boundary strictly enforce the following execution limits [2]:
*   **Plan-Deterministic Invariance**: Identical validated plans strictly guarantee identical tool-call and callback sequences [2].
*   **Hard Boundaries**: Capped at 32 max steps [2], 300s runtime limits [2], and isolated process memory.
*   **Safety Isolation**: Absolute blocklist enforcement (such as shell blocks) and sandbox blast-radius restrictions checked at the API boundary [2].

---

## Continuous Integration & Testing

Our consolidated test suite validates the unified architecture on Python 3.11 and 3.12 [2]:

*   **Core Execution & Schemas**: Pytest test suites covering core functionality, swarms, and planners [2].
*   **Adversarial Security**: Evasion-proof evaluation suites validating policy, network, and step-count boundaries [2].
*   **Retrieval & Integration**: Mocked and vectorized regression tests validating semantic accuracy and context grounding [2].

---

## Consultancy Operations

Axiom LLC provides dedicated systems architecture and engineering implementation services [2]:
*   Deterministic runtime layout design
*   Secure agent policy and rollback integration
*   Context-grounded knowledge boundaries (RAG)
*   High-throughput tool calling pipelines
*   Client demonstration and containerized cloud deployment setup

**axiom.co@proton.me · [axiom-llc.github.io](https://axiom-llc.github.io)** [2]
