# Changelog

Format: Keep a Changelog (keepachangelog.com/en/1.1.0/)
Versioning: Semantic Versioning (semver.org)

---

## [2.0.0] — 2026-03-06

### Added
- Interactive mode (--interactive / -i)
- Pydantic schema validation at plan boundary before tool invocation
- examples/: single-agent, iterative refinement, swarm demonstrations
- autonomous-business.sh, code-review.sh, iterative-coder.sh, research-agent.sh
- competitive-intelligence-swarm.sh, parallel-swarm.sh, recursive-self-improvement-swarm.sh
- templates/: 12 production operational domain templates
- compliance-audit, cybersecurity, due-diligence, healthcare-rcm, hedge-fund,
  insurance-claims, law-firm, msp, recruiter, revenue-monitor, solo-agency, supply-chain
- apex/benchmarks/: empirical concurrency data; practical ceiling 4 parallel processes
- .gitattributes: linguist override for correct Python language detection
- CI badge in README

### Changed
- All core types: frozen dataclasses; State updated via dataclasses.replace() only
- run() in core/loop.py is now a pure function
- Memory tools refactored to closure pattern: make_memory_tools(db_path)
- Config resolved once at startup, passed explicitly; no globals
- README restructured: Design Axioms, Data Flow, Exit Codes, Extending APEX

### Fixed
- Tool timeout: SIGALRM-based, enforced at 300s per invocation

---

## [1.0.0] — (pre-release development)

Initial working implementation. NL → JSON plan → deterministic tool execution.
Core tools: shell, read_file, write_file, http_get, memory_read, memory_write.
SQLite-backed persistent memory. --dry-run and --trace flags.

---

[2.0.0]: https://github.com/axiom-llc/apex-cli/releases/tag/v2.0.0
