# Special Organization Repository — `.github`

Welcome to the internal configuration and branding repository of the **Axiom LLC** GitHub organization.

This is a special repository used by GitHub to store organization-level assets, automated deployment actions, and the global organization landing page.

---

## 1. Directory Structure

*   **`profile/README.md`** — The public-facing landing document shown on the Axiom LLC organization overview page (`github.com/axiom-llc`).
*   **`workflows/deploy-pages.yml`** — GitHub Action runner automating static page deployment from the `docs/web/` directory of our core `axiom` repository.
*   **`README.md`** — This file. Serves as the repository-level documentation page.

---

## 2. Continuous Integration Workflow (`deploy-pages.yml`)

The workflow file at `.github/workflows/deploy-pages.yml` automates the publishing pipeline for our public website. It is configured to run on every push to the `main` branch, targeting changes in `docs/web/` to compile and publish our static landing page to GitHub Pages.

---

## 3. Local Sync & Development

To update either the profile README or this code-view document, apply changes locally and push to main:

```bash
cd /home/u/c/apps/.github

# Keep profile and repository READMEs aligned
cp README.md profile/README.md

# Stage, commit, and push
git add README.md profile/README.md workflows/deploy-pages.yml
git commit -m "chore: synchronize organization profiles and actions"
git push origin main
