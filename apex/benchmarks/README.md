# APEX Scenario & Retrieval Evaluation Suite

This directory contains automated testing and benchmarking scripts used to measure the accuracy, speed, and safety of the APEX runtime under enterprise workloads.

---

## 1. Benchmarking Targets

### A. RAG Grounding Accuracy (`eval_rag.py`)
*   **Dataset**: `eval_rag_dataset.json` contains curated reference questions, ground-truth context, and expected facts.
*   **Evaluation Metric**: Evaluates vector retrieval precision and generation grounding (measuring whether the model hallucinates or adheres strictly to retrieved passages).

### B. Thread-Safe Concurrency (`parallel_codegen.py`)
*   **Mechanism**: Spawns multiple parallel workers compiling complex files concurrently.
*   **Evaluation Metric**: Verifies database locking states, file lock handling, and multi-agent execution consistency under high I/O workloads.

---

## 2. Running the Benchmarks

To execute local benchmark runs and serialize performance scoring profiles to `results/`:

```bash
# Execute RAG precision evaluation
python3 apex/benchmarks/eval_rag.py

# Execute parallel code generation concurrency tests
python3 apex/benchmarks/parallel_codegen.py
```
