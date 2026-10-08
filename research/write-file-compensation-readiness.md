# Write-file compensation readiness

Date: 2026-09-11. Decision: compensation implementation remains blocked.
This is a repository-local evidence audit, not approval of a compensation policy.

## Question and scope

Can the existing ASON rollback helper safely compensate APEX `write_file`?
No: it produces a deletion plan without establishing original absence, prior
contents, outcome, current version, or authority. Define those contracts before
adding executable compensation. The completed durable ledger is a prerequisite,
not evidence that these additional contracts exist.

Source snapshots: ASON `be0ca453c7e401b1fb8893639d66f80d0f478fe5`, APEX
`13ae4233e5fea3e1e6ea91e9f18cdbd4d6961d7f`; research baseline `af7221f`.
Links below resolve in the sibling repository workspace; recheck snapshots before
using this note to implement changes.

## Observed exposure

- [ASON rollback](../axiom-ason/ason/rollback.py), `generate_rollback`, reads only
  step/tool/arguments from events in reverse order. It maps `write_file` to
  `delete_file`, then constructs a new local policy with an empty tool allowlist.
  It neither reads ledger outcomes nor carries original policy provenance.
- [Validator](../axiom-ason/ason/validator.py), `validate`, accepts that generated
  deletion under its generated local policy. Empty allowlist means no additional
  tool restriction. This is policy-shape acceptance, not compensation approval.
- [Executor](../axiom-ason/ason/executor.py), `submit`, does not invoke rollback;
  [schema](../axiom-ason/ason/schema.py) has no durable approval identity.
  `rollback_on_failure` does not cause automatic compensation. This audit does
  not demonstrate an automatic deletion vulnerability.
- [APEX tools](../axiom-apex/apex/core/tools.py), `write_file_effect`, overwrites
  bytes and may create parent directories; its output is only `bytes_written`.
  There is no durable preimage or resource version. Deletion cannot restore an
  overwritten file; it also does not reverse created directories.
- [Registry](../axiom-apex/apex/core/toolloader.py), `build_registry`, has no
  built-in `delete_file`, but user/MCP tools extend and can override the registry.
  Thus built-in absence limits present execution, not future/custom exposure.
- [History](../axiom-apex/apex/history.py) records accepted plans and conservative
  effect states. It has no tool-specific preimage or compensation authority.
  [Ledger tests](../axiom-apex/tests/test_effect_ledger.py) cover ambiguous forward
  dispatch; this audit does not rerun or reopen that accepted milestone.
- [Rollback tests](../axiom-ason/ason/tests/test_rollback.py) explicitly expect
  deletion generation. Their passing result establishes existing behavior, not
  the safety of the proposed inverse.

## Minimum reproducible experiment

Run from the AXIOM project root with the source dependencies installed. This
uses a temporary event database and never submits or executes the generated plan.
The two histories differ in outcome but expose identical arguments to the helper.
Success criterion for the audit: both generate a policy-accepted deletion,
confirming that outcome alone cannot protect this helper. If either assertion
fails, re-evaluate the finding against the changed source.

```python
import json
import sqlite3
import tempfile
from pathlib import Path
from ason.rollback import generate_rollback
from ason.validator import validate

with tempfile.TemporaryDirectory() as directory:
    db = Path(directory) / "runs.db"
    with sqlite3.connect(db) as conn:
        conn.execute("CREATE TABLE events (run_id TEXT, step INTEGER, tool TEXT, args_json TEXT, result_json TEXT)")
        for run, result in [("success", {"bytes_written": 3}), ("failure", {"error": "unknown"})]:
            conn.execute("INSERT INTO events VALUES (?, 0, 'write_file', ?, ?)",
                         (run, json.dumps({"path": "example.txt", "content": "new"}), json.dumps(result)))
    for run in ("success", "failure"):
        request = generate_rollback(run, db_path=db)
        assert request is not None
        assert [(s.tool, s.args) for s in request.plan.steps] == [("delete_file", {"path": "example.txt"})]
        assert validate(request).accepted
        print(f"{run}: deletion generated; policy accepted; no effect dispatched")
```

Observed with Python 3.12.9 and live source on the snapshots above: both cases
passed. Existing rollback and validator suites: **13 passed**. These synthetic
rows demonstrate the helper's query semantics, not a new end-to-end crash test.

## Required decisions and falsifiable implementation gates

| Contract | Missing decision / requirement | Required evidence before enabling compensation |
| --- | --- | --- |
| Approval | An application/policy owner must select who may authorize compensation, whether authorization is prior or fresh, its resource/action scope, and expiration/revocation behavior. Bind authorization to run, step, accepted plan and tool semantics; a newly constructed permissive policy is insufficient. | Missing, wrong-run, altered-plan, out-of-scope and revoked/expired authorization all prevent dispatch under the selected rules. |
| Inverse and preimage | Owner must choose supported file semantics: existing-file restore versus newly-created-file removal, metadata obligations, directory handling, symlinks/hardlinks, path identity and excluded resources. Capture required prior state durably before forward mutation; define retention/access controls. | Existing bytes and required metadata restore exactly; new-file handling is explicitly tested; unsupported resource types fail before mutation; missing/corrupt preimage blocks compensation. |
| Concurrency | Select an enforceable ownership/version primitive for the supported filesystem and all writers. A hash check followed by an ordinary write/delete has a race and is insufficient. | An independent writer between check and mutation cannot be clobbered; identity changes and version mismatch stop safely. If arbitrary writers cannot be excluded, do not enable restorative compensation. |
| Outcome reconciliation | Define how to distinguish not-applied, applied, and unknowable forward and inverse outcomes, including partial writes. Matching bytes alone does not prove which actor wrote them. | Crash injection around both forward and inverse intent/dispatch/outcome commits yields a proven safe action or explicit unresolved/manual state, never blind retry. |
| Durable inverse execution | Specify a compensation identity, durable intent/outcome binding and recovery behavior under the selected tool/authority contracts. Do not infer these from forward ledger state. | Repeated recovery cannot dispatch an unapproved inverse or repeat an ambiguous inverse; completed inverse handling is deterministic. |

Assumptions for any first increment must be explicit: one executor, stable trusted
tool/configuration, a chosen resource-ownership model, and process-crash semantics
only. No exactly-once, host-power-loss atomicity, provider reconciliation, or
restoration of arbitrary filesystem state is established by this audit.

## Integration path and exact next dependency

The smallest immediate safety opportunity is a separate ASON change that makes
`generate_rollback` fail closed for `write_file`, with a clear manual-review
result/diagnostic and updated tests/docs. It removes a misleading executable
inverse without needing to invent compensation authority. Preserve the helper's
public interface where possible; ensure no caller interprets absence as success.
This is proposed follow-up, not implemented or authorized policy in this note.

Actual compensation coding must wait for an explicit owner-approved authority
and resource-semantics contract covering the table above. Then implement only one
supported file-effect class and its crash/concurrency tests in APEX, with ASON
carrying the chosen authorization contract. Do not implement all effects or
weaken ambiguous-outcome recovery to make rollback appear available.
