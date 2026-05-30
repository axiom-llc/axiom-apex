# APEX Blueprints & Examples

This directory serves as the centralized blueprints and deployment surface of the Axiom LLC stack. It holds highly practical, runnable, and production-tested systems demonstrating APEX integrated with dashboards, telephony channels, and multi-agent coordination swarms.

---

## 1. Directory Structure

*   **`logistics-dashboard/`** — Full-stack logistics processing system containing Python database ingestion scripts, Dash verification interfaces, and SQLite ledger recorders.
*   **`voice-agent/`** — Serverless telephony agent deploying Gemini reasoning models behind Twilio webhook routing inside Docker containers.
*   **`cli_demos.sh`** — A comprehensive, executable bash script demonstrating high-concurrency swarms, iterative code repair, and research task flows.
*   **`test_logistics.py`** — Regression testing pipeline validating compliance parsing.

---

## 2. Operating the Centralized CLI Blueprint (`cli_demos.sh`)

The `cli_demos.sh` script is an active showcase of complex scripting patterns, displaying parallel execution, feedback loops, and multi-agent coordination.

### A. Parallel Task Execution
Demonstrates concurrent process spawning to evaluate planetary reports in parallel:
```bash
apex "compile weather report for Mars to ~/mars.txt" &
apex "compile weather report for Venus to ~/venus.txt" &
wait
```

### B. Iterative Repair Loop
Executes code generation and parses compiler warnings in a feedback loop, invoking APEX to fix errors automatically before re-running:
```bash
for i in $(seq 1 5); do
    python3 script.py 2> error.log && break
    apex "read script.py and error.log, patch the syntax errors, and write back to script.py"
done
```

### C. Synthesizing Swarms
Orchestrates multiple parallel worker prompts to query distinct aspects of a topic, merging their findings into a single structured index file:
```bash
for i in $(seq 1 4); do
    apex "research segment $i of quantum computing, write to ~/segment-$i.txt" &
done
wait
apex "read ~/segment-1.txt ... ~/segment-4.txt and compile a single technical whitepaper to ~/quantum.txt"
```

To run all integrated CLI demos in sequence, execute the master file:
```bash
chmod +x cli_demos.sh
./cli_demos.sh
```
