# Public Web Registry Assets

This directory houses the static web assets, visual diagrams, and public portfolio index files defining the online surface of Axiom LLC (`axiom-llc.github.io`).

---

## 1. File & Asset Inventory

*   **`index.html`** — The corporate landing page. Features structural overview blocks, repository links, pricing consultancy outlines, and direct communication panels.
*   **`architecture/system-stack.svg`** — Visually maps the system hierarchy, tracing paths from language model planning down to safe local sandboxes.
*   **`favicon.svg`** — Scalable vector logo for web browsers.
*   **`LICENSE`** — MIT usage license.

---

## 2. Architecture Diagram (`system-stack.svg`)

The `system-stack.svg` is an optimized, dark-mode vector graphic illustrating our engineering stack. It has been designed with re-centered grids, expanded card elements (`540px` widths), and offset connection paths to guarantee high legibility across all diagnostic browsers.

---

## 3. Local Audit & Deployment

### Local Verification
To test site layouts, asset links, and CSS styles locally on your machine, launch the Python built-in server:
```bash
python -m http.server -d /home/u/c/apps/docs/web/ 8000
```
Open your web browser and navigate to `http://localhost:8000` to verify changes.

### Automated Continuous Integration
This subfolder is deployed automatically to GitHub Pages on every push to the `main` branch, managed by the GitHub Action workflow defined at `.github/workflows/deploy-pages.yml`.
