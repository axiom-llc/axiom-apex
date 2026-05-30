# Independent Research Surface — Theoretical AI Systems

This directory houses the formal, mathematical, and computer-science research produced by Axiom LLC. Our focus is the design and analysis of plan-deterministic system architectures, execution safety profiles, and recursive optimization loops.

---

## 1. Core Publications

### 📄 Deterministic Execution Contracts for LLM Agent Systems (`tacon2026_apex_ason_deterministic_execution_contracts.tex`)
*   **Axiom Proof**: Formalizes plan-deterministic verification boundaries. It models how probabilistic language outputs can be compiled into structured execution loops bounded by static safety contracts, and outlines programmatic rollback models on execution failures.
*   **Format**: Academic LaTeX. Includes built-in package definitions and bibliography layouts.

### 📄 AI Loop Architecture Taxonomy (`ai-loop-architecture-taxonomy.md`)
*   **Core Focus**: Standardizes and classifies agent execution loop topologies.
*   **Categories**: Maps patterns from single-prompt linear plans up to advanced human-in-the-loop and recursive self-improvement swarms.

### 📄 Recursive Hyper-Optimization (`recursive-hyper-optimization.md`)
*   **Core Focus**: Explores the computational bounds, token efficiency limits, and state-explosion dynamics of self-improvement loops (BDSO).
*   **Theory**: Outlines mathematical formulas governing convergence behaviors and convergence safety bounds inside optimization engines.

---

## 2. Compiling LaTeX Documents

The main academic paper is written in LaTeX. To compile the file into a publication-ready PDF:

### Requirements
Ensure you have the required modular LaTeX packages installed (specifically for Arch Linux):
```bash
sudo pacman -Syu texlive-bin texlive-basic texlive-latex texlive-latexextra
```

### Compilation Command
Navigate to the directory and run the compiler:
```bash
cd /home/u/c/apps/docs/research/
pdflatex tacon2026_apex_ason_deterministic_execution_contracts.tex
```

This generates a standardized PDF file (`tacon2026_apex_ason_deterministic_execution_contracts.pdf`) in the same directory.
