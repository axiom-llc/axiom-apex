# APEX — Command-Line Operating System for Autonomous Business Units

[![PyPI Version](https://img.shields.io/pypi/v/axiom-apex?color=blue)](https://pypi.org/project/axiom-apex/)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](https://opensource.org/licenses/MIT)
[![Python Version](https://img.shields.io/badge/python-3.11%20%7C%203.12-blue)](https://pyproject.toml)

Welcome to **APEX**, the central, production-grade system runtime developed by **AXIOM LLC**. APEX is a minimalist command-line operating system designed to orchestrate and run deterministic **Autonomous Business Units (ABUs)** on standard POSIX environments.

By consolidating previously fragmented repositories into a single unified monorepo, APEX eliminates version drift, enforces strict schema invariance, and runs parallel workloads with hard OS-level process isolation.

---

## 1. The 18 Autonomous Business Unit (ABU) Verticals

APEX includes 18 production-ready business automation templates located inside the templates workspace. These are not trivial examples; they are complete, functional shell workflows designed to run automated workloads, manage risks, and drive recurring revenue:

| Autonomous Business Unit (ABU) | Target Role / Industry | Primary Automated Action |
| :--- | :--- | :--- |
| **`solo-agency.sh`** | Solo Consultants & Agencies | Automates client qualification, proposals, kickoffs, time tracking, and invoices. |
| **`revenue-monitor.sh`** | Micro-SaaS Founders | Runs a complete, self-owned Uptime Monitoring SaaS business with billing ledgers. |
| **`law-firm.sh`** | Solo Law Practices | Handles client intakes, conflict-of-interest checks, timesheets, and legal invoicing. |
| **`compliance-audit.sh`** | Infosec & Compliance Officers | Continuous system audit checking server logs against SOC 2, HIPAA, PCI, and GDPR. |
| **`cybersecurity.sh`** | Security Operations (SecOps) | Scans assets, parses authentication logs, checks CISA vulnerabilities, and isolates threats. |
| **`healthcare-rcm.sh`** | Medical Practices & Billing | Performs claim scrubbing (CPT/ICD-10), denials root-cause, and AR sweeps. |
| **`due-diligence.sh`** | Corporate M&A & Private Equity | Runs parallel research agents to write comprehensive corporate investment memos. |
| **`deal-flow.sh`** | VC & Angel Investors | Triages pitch decks against investment criteria and drafts professional feedback. |
| **`hedge-fund.sh`** | Quantitative Portfolio Managers | Ingests market active lists and compiles pre-market investment briefs. |
| **`supply-chain.sh`** | Procurement & Risk Officers | Monitoring vendor news feeds via GDELT API to score financial/geopolitical risk. |
| **`venture-bootstrap.sh`** | Venture Builders & Incubators | Compiles raw startup ideas into market research, business models, and MVP specs. |
| **`recruiter.sh`** | Talent Acquisition Managers | Performs job description matching, candidate resume scoring, and personal outreach. |
| **`insurance-claims.sh`**| Insurance Carriers & TPAs | Automates claims triage, severity grouping, and fraud red-flag checks. |
| **`msp.sh`** | Managed Service Providers | Performs client server SSH checks and triggers audio text-to-speech alerts. |
| **`content-engine.sh`** | Search Engine Marketing (SEM) | Scrapes tech signals, compiles content briefs, drafts posts, and scores SEO. |
| **`opportunity-scanner.sh`**| Business Development | Evaluates Product Hunt/HN gaps and maps them to technical stack capabilities. |
| **`standardize-templates.sh`**| DevOps Infrastructure | Enforces date/audio portability across different Unix operating system targets. |

---

## 2. Core System Invariants & Guardrails

Every process and component inside this monorepo strictly complies with these four architectural guardrails:

1.  **Pure Functional Transition Kernels**: The core execution engine (`apex/core/loop.py`) operates as a pure function: `run(Task, Config, Registry) -> State`. No global variables, hidden side-effects, or implicit mutable states are permitted.
2.  **OS-Level Process Isolation**: Multi-agent swarm workers (`apex/core/swarm.py`) run as isolated operating system processes via `subprocess.Popen`. A thread crash or infinite loop inside a worker cannot propagate and crash the parent master thread.
3.  **Two-Stage Paranoid Security Gate**: Before any generated plan enters execution, it is checked by local, deterministic Regex prefilters (intercepting commands like `rm -rf /` or `chmod 777`), followed by a strict security audit conducted in-process by `gemini-3.1-flash-lite`.
4.  **Asymmetric Embedding Precision**: The integrated RAG engine (`apex/core/rag.py`) utilizes asymmetric embedding task configurations (`RETRIEVAL_DOCUMENT` vs `RETRIEVAL_QUERY`) to maximize semantic vector search precision.

---

## 3. Quickstart & Installation

### Prerequisites
*   Python 3.11 or 3.12 (Unix-based operating system recommended for local timeout mechanics).
*   A valid Gemini API key.

### Step 1: Install from PyPI
Install the package directly into your virtual environment:
```bash
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install axiom-apex
```

### Step 2: Configure Keys
```bash
export GEMINI_API_KEY="your_api_key_here"
```

### Step 3: Run Your First Task
Submit a direct task straight to the compiler:
```bash
apex "search for error traces in /var/log/syslog and count their occurrences"
```

### Step 4: Run the Complete Regression Suite
```bash
pytest apex/tests/ -q
```

---

## 4. Contact & Registry
*   **Company**: `axiom.co@proton.me`
*   **Development**: `axiom.de@proton.me`
*   **Web Surface**: [`axiom-llc.github.io`](https://axiom-llc.github.io)
