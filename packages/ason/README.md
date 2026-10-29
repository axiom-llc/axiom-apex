# AXIOM ASON

ASON is AXIOM's pre-execution policy enforcement layer for APEX. Version
`0.3.0` is current source and requires Python 3.11+ plus APEX 3.2.0 or newer.
It validates caller-supplied plans; it is not a natural-language planner and
does not independently execute tools.

## System boundary

- **APEX** — execution/runtime.
- **ASON** — pre-execution policy enforcement.
- **RAG** — retrieval/storage HTTP service and library.

## Policy enforcement
ASON validates and governs plan submission to APEX before any execution begins. Plans that violate policy are rejected at the API boundary — not at runtime.

Enforcement at validation time:
- `len(plan.steps) ≤ policy.max_steps`
- No step invokes a tool in the blocked set (`shell` is always blocked)
- If `allowed_tools` is non-empty, every step's tool must appear in it
- `blast_radius` classification blocks tools by impact envelope:
  - `none` — blocks filesystem/memory writes and network tools (read-only)
  - `local` — blocks `http_get`, `http_post`, and `rag_multi_query` (local effects only)
  - `network` — no additional blocks

## APEX Contract
Supply an ASON request to `ASONExecutor.submit` or `ason submit`:

```json
{
  "plan": {"steps": [{"tool": "read_file", "args": {"path": "/tmp/input.txt"}}]},
  "policy": {
    "max_steps": 16,
    "allowed_tools": ["read_file"],
    "blast_radius": "local",
    "rollback_on_failure": false
  }
}
```

ASON validates every step against the supplied policy before making an HTTP
request. Authorized dispatch also requires a caller-supplied `authority_ref`
(`ASON_AUTHORITY_REF` or `--authority-ref`). ASON generates a unique
authorization ID and sends this distinct request to `POST /authorized-run`, with
`Content-Type: application/json` and `X-Apex-Key` when configured:

```json
{
  "plan": {
    "goal": "Execute ASON-approved plan",
    "steps": [
      {"type": "tool", "name": "read_file", "args": {"path": "/tmp/input.txt"}},
      {"type": "halt", "reason": "ASON-approved plan complete"}
    ]
  },
  "authorization": {
    "authorization_id": "<generated UUID>",
    "approved_plan_digest": "<SHA-256 of the exact APEX plan>",
    "policy_digest_or_ref": "<SHA-256 of the validated policy>",
    "authority_ref": "<caller-supplied reference>",
    "decision": true
  }
}
```

Tool order, names, and JSON arguments are preserved. The adapter adds only the
fixed goal, tool-step tags, terminal halt, and authorization metadata; it sends
neither `task` nor the policy body. APEX's separate `{"task": ...}` interface
retains planning for direct callers, but ASON never uses it. ASON governs the
submitted policy and transmits its digest/reference, exact approved-plan digest,
authorization identity, and caller-supplied authority reference.

Requires APEX 3.2.0 or newer. ASON translates approved steps into APEX tool
steps followed by a halt and submits the exact plan plus authorization binding
to `POST /authorized-run`. Older APEX versions fail closed because that route
does not exist. APEX validates the entire plan and authorization binding against
its active registry before executing without replanning.
Its 32-step ceiling includes the final halt (at most 31 tool calls). Schema-invalid
or unavailable tools are rejected by APEX before execution. Unclassified custom
tools are rejected by ASON; deployed tool implementations must match their stated
classification. Policy enforcement assumes callers cannot bypass ASON using the
APEX API key directly and that trusted application code chooses the policy.
APEX schema validation is not a second policy engine.

`accepted` reports ASON policy approval. Check `error` and
`apex_response.exit_code` for execution success. The CLI exits nonzero on policy,
transport, APEX validation, or execution failure.

The integration suite checks equality of the submitted plan, APEX response,
recorded plan, and executed tool arguments with replanning disabled. It also
checks that later policy violations prevent submission and later APEX schema
errors prevent earlier effects. This establishes the current submission boundary;
recorded-plan replay is also checked with replanning disabled, and dry/simulate
replay does not execute tools. Live replay uses APEX's durable same-run recovery:
completed steps reuse recorded results, while ambiguous dispatch states block
further execution. Authorized runs also persist the authorization identity,
approved-plan digest, policy digest/reference, authority reference, and decision
before dispatch and re-check that durable binding during recovery. These checks
do not establish exactly-once external effects or a stronger remote-effect
guarantee.

## Rollback
The optional `generate_rollback` helper inspects run events in reverse order. It returns `None` for `write_file` and emits explicit manual-review guidance: automatic compensation is unavailable until compensation authority, durable preimage, concurrency/version safety, and outcome reconciliation contracts are defined. It never generates `delete_file` as an inverse of `write_file`. `shell` invocations retain their manual-review warning; other operations have no automatic inverse. `None` means no rollback plan is available, not that compensation succeeded. The helper is not invoked automatically by the executor; `rollback_on_failure` currently does not trigger automatic rollback.

## Installation

ASON 0.3.0 and its required APEX 3.2.0 are not yet published as GitHub
Releases. RAG 1.5.0 is published; the published APEX 3.1.1 baseline does
not satisfy ASON's `axiom-apex>=3.2.0` dependency. Do not use a bare
`pip install axiom-ason` as a path to this integrated source state.

For development, use Python 3.11 or 3.12 on Linux/macOS (APEX uses POSIX
signals). Windows users need a Linux environment such as WSL. From a directory
where these repository names do not already exist:

```bash
git clone https://github.com/axiom-llc/axiom-rag.git
git clone https://github.com/axiom-llc/axiom-apex.git
git clone https://github.com/axiom-llc/axiom-ason.git
cd axiom-ason
python3 -m venv .venv
source .venv/bin/activate
python -m pip install ../axiom-rag -e ../axiom-apex -e . 'pytest>=8'
python -m pip check
```

Use matching RAG 1.5.0, APEX 3.2.0 and ASON 0.3.0 source versions, declared
in each checkout's `pyproject.toml`. If the checkouts already exist, use those
instead of cloning over them. Dependencies require package-index access.

These commands install source checkouts; they do not publish artifacts.
See [APEX release gates](https://github.com/axiom-llc/axiom-apex/blob/main/RELEASE.md)
and the [published RAG release](https://github.com/axiom-llc/axiom-rag/releases/tag/v1.5.0).

## Implementation evidence

| Inspect | What it demonstrates |
| --- | --- |
| [Policy validator](ason/validator.py) | Step limits, tool allowlists and impact classifications before submission. |
| [Policy tests](ason/tests/test_validator.py) | Accepted plans and explicit rejection cases. |
| [APEX integration tests](ason/tests/test_apex_integration.py) | Exact-plan dispatch, failure propagation and authorization/recovery bindings with provider calls mocked. |

These are project-controlled implementation and test artifacts, not evidence of
customer deployment or independent security assurance.

## Validation
Offline tests cover policy, exact APEX execution, and failure propagation across these categories:
- CAT1: blast_radius rejection
- CAT2: max_steps violation
- CAT3: tool allowlist enforcement
- CAT4: malformed plan (schema-level)
- CAT5: timeout elicitation
- CAT6: concurrent isolation

```bash
python -m pytest ason/tests/ -q
```

Component CI builds matching wheels from RAG and APEX `main` plus the ASON
revision under test, then installs them together using their package metadata.
It runs the complete suite outside the checkouts with `--import-mode=importlib`
so ASON exercises the installed APEX runtime. Full portfolio/container checks
remain in `axiom-infra`.

CI checks out the public RAG and APEX repositories at `main` with
`persist-credentials: false`. It records dependency revisions and verifies that
checkout credentials are removed before package build and test execution.

## Usage

Set the APEX target and an authoritative reference through the environment.
`authority_ref` is an opaque reference supplied by the caller/Harness; ASON does
not invent human approval or authority.

```bash
export APEX_URL=http://127.0.0.1:8080
export APEX_API_KEY='replace-with-the-configured-key' # when APEX requires one
export ASON_AUTHORITY_REF='replace-with-the-caller-authority-reference'
ason submit plan.json
```

The CLI also accepts `--authority-ref REF` for per-submission binding.

## Related AXIOM components

- [APEX](https://github.com/axiom-llc/axiom-apex) — execution/runtime.
- [RAG](https://github.com/axiom-llc/axiom-rag) — required by current APEX source.
- [Infra](https://github.com/axiom-llc/axiom-infra) — local portfolio integration.

## License

AXIOM-authored software is available under the [MIT License](LICENSE).
