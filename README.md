# AXIOM LLC — Unified AI Systems Monorepo

Welcome to the central, production-grade system repository of AXIOM LLC. This repository houses the entire, highly consolidated AI operating system stack, theoretical research publications, static web surfaces, and continuous delivery pipelines.

By consolidating previously disjointed repositories into a single unified monorepo, we eliminate transactional version drift, simplify continuous integration, and ensure atomic dependency resolution across all engineering layers.

---

## 1. Structural Architecture

This monorepo is engineered to function as a unified operational stack. Below is the comprehensive file and directory topology mapping our systems from the execution kernel up to public-facing documentation and continuous integration pipelines:

```
.
├── apex/                             # Core Execution Engine Package
│   ├── benchmarks/                   # Automated Testing & Optimization Datasets
│   │   ├── eval_rag_dataset.json     # Grounding evaluation corpus for RAG queries
│   │   ├── eval_rag.py               # Document retrieval accuracy scoring engine
│   │   ├── parallel_codegen.py       # Multi-threaded code generation test harness
│   │   ├── results/                  # Serialized performance scoring JSONs
│   │   └── tasks.json                # Standard 12-task optimization benchmark suite
│   ├── bench.py                      # Local benchmark runner & BDSO cycle controller
│   ├── config.py                     # Frozen Global Configuration Dataclass
│   ├── core/                         # Pure Functional State & Exec Kernel Submodules
│   │   ├── api_clients.py            # Resilient HTTP REST adapters with retry loops
│   │   ├── __init__.py               # Core sub-package initialization
│   │   ├── loop.py                   # Pure functional transition engine: run() -> State
│   │   ├── planner.py                # Schema-validated JSON plan generator
│   │   ├── rag.py                    # Embedded, in-process semantic search engine
│   │   ├── rollback.py               # Programmatic execution failure rollbacks
│   │   ├── schema.py                 # Valid policy structures and safety parameters
│   │   ├── state.py                  # Immutable state transitions & database memory
│   │   ├── swarm.py                  # Multi-agent process-isolated swarm coordinator
│   │   ├── tools.py                  # Process-isolated side-effect tool definitions
│   │   ├── trace.py                  # JSONL trace logs, exporters, and simulator
│   │   ├── types.py                  # Frozen data modeling schemas (Step, Plan, Event)
│   │   └── validator.py              # Regex prefilters & LLM plan auditors (Paranoid)
│   ├── examples/                     # Ready-to-deploy blueprints and automation runners
│   │   ├── cli_demos.sh              # Multi-agent swarm and CLI execution demo shell
│   │   ├── logistics-dashboard/      # Real-time dashboard (Flask + Dash + SQLite)
│   │   ├── README.md                 # Examples subdirectory guide
│   │   ├── test_logistics.py         # Logistics dashboard verification suite
│   │   └── voice-agent/              # Telephony voice agent (Twilio + Flask + Docker)
│   ├── history.py                    # Persistent SQLite trace and metrics recorder
│   ├── __init__.py                   # Package-level initialization
│   ├── llm.py                        # Thin LLM delegation and execution layer
│   ├── __main__.py                   # CLI entry-point and subcommand dispatcher
│   ├── mcp.py                        # Model Context Protocol (MCP) server adapter
│   ├── prompt.txt                    # System prompt instructions and planner guidelines
│   ├── providers.py                  # Platform API integrations (Gemini & Ollama)
│   ├── README.md                     # APEX Package Engine README
│   ├── server.py                     # Flask-backed programmatic execution HTTP API
│   ├── templates.json                # Consolidated configuration safety policy profiles
│   ├── templates.py                  # Profile loader and local asset manager
│   └── tests/                        # Component-specific regression testing suite
├── docker-compose.yml                # Unified single-container service orchestration
├── Dockerfile                        # Multi-stage optimized application container definition
├── docs/                             # Conceptual, Academic, & Visual branding assets
│   ├── README.md                     # Docs Surface Directory Index
│   ├── research/                     # Mathematical papers and taxonomies
│   └── web/                          # Static registry index, diagrams, and site assets
├── .env.example                      # Reference local environment variable template
├── .gitignore                        # Global repository ignore specifications
├── LICENSE                           # Software use compliance certificate (MIT)
└── pyproject.toml                    # Declarative package build and dependency manager
```

---

## 2. Global System Invariants

Every subsystem and component inside this monorepo strictly complies with the following architectural invariants:

1.  **Pure Functional Transition Kernels**: The core execution engine (`apex/core/loop.py`) operates as a pure function: `run(Task, Config, Registry) -> State`. No global variables, hidden side-effects, or implicit mutable states are permitted.
2.  **Explicit Execution Boundaries**: Tool calls are bounded at runtime by a hard ceiling of 32 execution steps, a maximum tool execution timeout of 300 seconds, and strict process isolation.
3.  **Strict Schema Invariance**: Planners generate execution sequences in raw JSON. These are parsed and structurally validated against strict Pydantic schemas before entering the execution path.
4.  **Static Security Gateways**: Local execution policies strictly limit network access and filesystem write areas at the API boundary before execution, verified in-process.

---

## 3. Boostrap & Environment Initialization

To initialize and run this consolidated stack locally, follow these instructions.

### Prerequisites
*   Python 3.11 or 3.12 (Unix-based operating system recommended for SIGALRM timeout mechanics).
*   A valid Gemini API key.
*   (Optional) Docker & Docker Compose for containerized deployments.

### Step 1: Clone & Navigate
```bash
git clone git@github.com:axiom-llc/axiom.git ~/c/apps/axiom
cd ~/c/apps/axiom
```

### Step 2: Establish Virtual Environment
```bash
python3.12 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install -e .
```

### Step 3: Bind Environment Parameters
Copy the reference template and configure your access keys:
```bash
cp .env.example .env
# Edit .env with your favorite editor to populate GEMINI_API_KEY and APEX_API_KEY
```

---

## 4. Run Protocols

### Local CLI Run
Submit a direct natural language task straight to the compiler:
```bash
apex "search for error traces in /var/log/syslog and count their occurrences"
```

### Local Development Test Run
Ensure your local environment passes all standard regression tests:
```bash
pytest apex/tests/ -q
```

---

## 5. Contact & Registry
*   **Company**: `axiom.co@proton.me`
*   **Development**: `axiom.de@proton.me`
*   **Web Surface**: [`axiom-llc.github.io`](https://axiom-llc.github.io)
