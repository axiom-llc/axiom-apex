# Unified Registry & Documentation Surface

This directory serves as the theoretical and public registry boundary of Axiom LLC, holding all independent academic publications, systems taxonomy catalogs, and static web deployment resources.

---

## Subdirectory Layout

*   `research/` — Peer-reviewed publications, technical preprints, and formal systems architecture blueprints.
*   `web/` — Static assets, structural charts, index files, and HTML templates defining the public organizational portfolio.

---

## 1️⃣ `research/` — Scientific and Systems Publications

All academic texts are written in markdown and TeX, exploring execution determinism, computing self-reference, and agent system coordination models.

### Core Publications Included:
*   **Deterministic Execution Contracts (`tacon2026_apex_ason_deterministic_execution_contracts.tex`)** — Formalizes plan-deterministic verification boundaries and structural state rollbacks on execution boundary breaches.
*   **AI Loop Architecture Taxonomy (`ai-loop-architecture-taxonomy.md`)** — Catalogs structural design strategies for recursive, sequential, and autonomous multi-agent loops.
*   **Recursive Hyper-Optimization (`recursive-hyper-optimization.md`)** — Explores computational limits, state explosions, and stabilization vectors inside optimization pipelines.

### Compilation Notes:
To verify and compile TeX documents:
```bash
cd research/
pdflatex tacon2026_apex_ason_deterministic_execution_contracts.tex
```

---

## 2️⃣ `web/` — Static Public Registry

Contains the portfolio surface of Axiom LLC, deployable directly to hosting surfaces (such as GitHub Pages) directly from the `docs/web/` directory.

### Components:
*   `index.html` — Base entry point documenting repository networks, consultancy services, and contact parameters.
*   `architecture/system-stack.svg` — Visual system topology charting layers from language model planning down to execution sandboxes.

### Local Verification:
To serve and audit the static web registry locally:
```bash
python -m http.server -d web/ 8000
```
Audit the local surface by opening `http://localhost:8000` in any diagnostic browser window.
