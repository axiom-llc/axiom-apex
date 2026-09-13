# Changelog

## [3.1.1] — Unreleased

- Require RAG >=1.5.0 and retain the migrated HTTP storage adapters, server-owned
  credentials and recovery, explicit target/namespace/space checks, and no retry
  or local-storage fallback after uncertain HTTP results.
- Prepare GitHub wheel/sdist distribution with exact-source builds, checksums and
  clean-install CI. RAG 1.5.0 must be released and download-verified first.
- Narrow release-facing metadata and ASON integration wording: recorded-plan
  execution is bounded; model generation is not deterministic, and automatic
  transactional rollback and stronger durability guarantees are not established.

Earlier implementation history remains in Git. This entry is not a publication record.
