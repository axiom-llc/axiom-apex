# axiom-harness

Minimal durable operational orchestration core for AXIOM.

`axiom-harness` owns bounded task progression across eligible execution resources. It does not own strategic prioritization, provider/model reasoning, domain-specific reward workflows, ASON authorization policy, or APEX effect execution/recovery.

## Status

Version `0.1.0` is the extracted generic vertical slice proven first inside the private experimental `reward-harness`. The reward-specific application remains separate.

This slice establishes:

- immutable `TaskSpec` and `ResourceSpec` identities;
- SQLite/WAL durable state with full synchronization;
- hard `$0.00` task cash ceiling;
- capability, mutation-class, and context-budget eligibility;
- exclusive task/resource leases with expiry recovery;
- immutable execution attempts;
- explicit `UNKNOWN` outcomes that are never automatically retryable;
- bounded retry requiring affirmative retry-safety evidence;
- deterministic SHA-256 result acceptance;
- separate acceptance and transactional canonical commit;
- at most one canonical result per task;
- machine-readable `axiom-harness/receipt-v1` completion receipts;
- restart/reopen recovery and fault-tested canonical commit rollback.

It intentionally does **not** yet implement provider adapters, dynamic quota/account state, sensitivity/autonomy policy, worktree isolation, event scheduling, a daemon, distributed coordination, or exactly-once external effects.

## Authority boundary

```text
Owner / Director
    ↓ WorkIntent
axiom-harness
    ↓ TaskSpec / lease / attempt
eligible executor
    ↓ candidate + evidence
axiom-harness
    ↓ deterministic acceptance + canonical commit
CompletionReceipt
```

Workers produce candidates. The Harness alone commits the canonical task result. `UNKNOWN` never implies retry safety.

## Run from source

Requires Python 3.11 or newer. The runtime uses only the Python standard library. From an authorized source checkout, run `make verify` (POSIX shell and Make required), or run the test suite directly:

```bash
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=. python -m unittest discover -s tests -p 'test_*.py' -v
```

For editable package installation, use `python -m pip install -e .` in a virtual environment; build tooling may require package-index access. Provider adapters and a hosted service are not included.

## Example

```python
from hashlib import sha256
from axiom_harness import HarnessStore, ResourceSpec, TaskSpec

result = b"accepted-result"

with HarnessStore("harness.sqlite3") as store:
    store.submit_task(TaskSpec(
        task_id="task-1",
        intent_ref="intent-1",
        domain="engineering",
        capabilities=("python",),
        expected_result_sha256=sha256(result).hexdigest(),
        mutation_class="M1",
        cash_ceiling=0.0,
        context_budget=4096,
        retry_budget=1,
    ))
    store.register_resource(ResourceSpec(
        resource_id="local-python",
        capabilities=("filesystem", "python"),
        maximum_mutation_class="M1",
        hard_zero_spend_eligible=True,
        context_limit=4096,
    ))
    lease = store.acquire_lease(
        "task-1", "local-python", b"bounded context", ttl_seconds=60
    )
    attempt = store.record_attempt(lease.lease_id, result=result)
    receipt = store.commit_accepted(attempt.attempt_id)
```

## Validation

```bash
make verify
```

The suite covers immutable identities, hard-zero-spend and capability filtering, context gates, exclusive leases, lease expiry/reopen recovery, deterministic acceptance, transactional canonical commit, duplicate-canonical exclusion, accepted-candidate restart recovery, commit fault rollback, explicit `UNKNOWN`, bounded retry, attempt immutability, and database reopen validation.

## Origin

Extracted only after the generic slice passed the complete `reward-harness` suite (`63/63`) and its existing verification script returned `ok`. No reward opportunity, payout, mail-routing, platform-policy, participant workflow, or mutable reward database state is included here.

## License

AXIOM-authored software is available under the [MIT License](LICENSE).
