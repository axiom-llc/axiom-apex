# Changelog

## [3.2.0] — Unreleased

- Bind provider profile identity into validation evidence.
- Bind effect recovery to the validated tool-registry contract.
- Bind durable ASON authorization evidence to accepted APEX runs.

## [3.1.1] — 2026-09-13

- Require RAG >=1.5.0 and retain the migrated HTTP storage adapters, server-owned
  credentials and recovery, explicit target/namespace/space checks, and no retry
  or local-storage fallback after uncertain HTTP results.
- Prepare GitHub wheel/sdist distribution with exact-source builds, checksums and
  clean-install CI. RAG 1.5.0 must be released and download-verified first.
- Narrow release-facing metadata and ASON integration wording: recorded-plan
  execution is bounded; model generation is not deterministic, and automatic
  transactional rollback and stronger durability guarantees are not established.
- Resolve provider/model identity once in immutable runtime configuration and
  emit a secret-free SHA-256 execution-profile digest in benchmark evidence.

Earlier implementation history remains in Git.
