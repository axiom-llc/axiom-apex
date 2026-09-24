# Distribution and release gates

Version 3.2.0 is unreleased; version 3.1.1 was published on 2026-09-13. This document prepares publication; it does not
authorize a tag, release, upload, or paid service.

## Decision

Use GitHub Releases with versioned tags, wheels, sdists, `SHA256SUMS`, and
`BUILD-INFO.json` (source SHA, timestamp, Python and build-tool versions).
Public release downloads use the existing GitHub account and need no new registry
credentials. [Release storage/bandwidth](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases)
supports these small assets; [standard public-repository CI](https://docs.github.com/en/billing/concepts/product-billing/github-actions)
is free. Ordinary validation uploads no Actions artifacts or caches.

[GitHub Packages](https://docs.github.com/en/packages/learn-github-packages/introduction-to-github-packages)
has no native Python registry. Immutable Git commit installs are a useful source
fallback, but require Git and consumer-side builds and still need the explicit
matching RAG dependency. A separate index adds hosting and maintenance without
improving this two-package chain. AXIOM PyPI publication is retired; old PyPI
releases are historical. Third-party dependency downloads may still use PyPI.

## Reproduce artifacts

From a clean checkout of the exact selected commit, using Python 3.11 or 3.12:

```bash
python -m venv /tmp/axiom-build-env
/tmp/axiom-build-env/bin/python -m pip install -r scripts/build-requirements.txt
/tmp/axiom-build-env/bin/python scripts/build-release.py /tmp/axiom-dist
cd /tmp/axiom-dist
sha256sum --check SHA256SUMS
```

The output directory must not exist. The builder always archives **HEAD**, never
uncommitted files. It builds the sdist, normalizes archive timestamps/ownership,
and builds the wheel from that sdist. `SOURCE_DATE_EPOCH` is the commit timestamp;
build tools are pinned. CI repeats the build and compares all checksums within
each Python environment. This does not promise identical hashes across arbitrary
Python/tool versions or lock all transitive runtime dependencies. Retain a
wheelhouse and `pip freeze`/installation report for a fully offline environment.

Pass `--tag v3.2.0` only when that existing tag points to HEAD and matches
`pyproject.toml`; mismatches fail before building. The builder never tags or publishes.

## Installation and integrity

Once separately authorized releases exist, download all assets for each required
package using first-party `gh` (public HTTPS links work without authentication):

```bash
gh release download v3.2.0 -R axiom-llc/axiom-apex --dir axiom-apex-dist \
  -p '*.whl' -p '*.tar.gz' -p SHA256SUMS -p BUILD-INFO.json
(cd axiom-apex-dist && sha256sum --check SHA256SUMS)
gh release download v1.5.0 -R axiom-llc/axiom-rag --dir axiom-rag-dist \
  -p '*.whl' -p '*.tar.gz' -p SHA256SUMS -p BUILD-INFO.json
(cd axiom-rag-dist && sha256sum --check SHA256SUMS)
python -m venv .venv
source .venv/bin/activate
python -m pip install axiom-rag-dist/axiom_rag-1.5.0-py3-none-any.whl axiom-apex-dist/axiom_apex-3.2.0-py3-none-any.whl
python -m pip check
```

Checksums detect changed bytes relative to the downloaded manifest, not an
independent identity guarantee. Before any future publication, verify
[GitHub release immutability](https://docs.github.com/en/code-security/concepts/supply-chain-security/immutable-releases)
in repository settings; do not assume a versioned URL or tag alone is immutable.
Future immutable releases also carry GitHub release attestations. Never replace
released assets or move a released tag; use a new version for corrections.

## Future release sequence (separate authorization required)

1. Re-verify the published immutable RAG `v1.5.0` assets, exact source SHA,
   checksums, installed version, `pip check`, imports and non-provider CLI in a
   fresh environment.
2. Review the exact APEX source SHA, release notes and metadata. Require green
   owning CI and Distribution checks on Python 3.11 and 3.12, matching wheel/sdist
   builds, clean installs outside checkouts, `pip check`, CLI and adapter smoke.
   APEX owning CI must retain its real kernel isolation probes.
3. Verify release immutability and zero-cost repository/runner eligibility for
   APEX. Update `Unreleased` wording/date only when actually releasing.
4. Only with explicit owner authorization, create/push APEX `v3.2.0` at its
   approved commit and dispatch its Distribution workflow with the explicit
   publication flag. Its publication validation **requires the published RAG
   1.5.0 assets**, verifies checksums, and installs both wheels in an isolated
   environment. Ordinary CI may continue to use exact pinned RAG source.
5. Verify downloadable APEX plus RAG together from outside source trees; check
   versions, dependency resolution, adapter behavior and CLI. Retain artifact
   hashes and source revisions as the release acceptance evidence.

The workflow validates both Python versions before release creation. Only the
release job receives `contents: write`; it verifies the checked-out tag still
matches the built revision. [gh release create](https://cli.github.com/manual/gh_release_create)
uses a draft to attach all assets before publication; `--verify-tag` prevents
implicit tag creation. It never overwrites an existing release. A failed upload
may leave a draft: inspect it and resolve manually before retrying, never clobber.
No PyPI publishing action, OIDC permission, or PyPI credential is used.

Source packaging and clean-install checks do not establish live deployment,
provider availability, exactly-once effects, host-power-loss atomicity, or
independent security assurance. Preserve the README's tested runtime boundaries.
