from hashlib import sha256
from pathlib import Path
import sqlite3
import tempfile
import unittest

from axiom_harness.harness import (
    ConflictError,
    EligibilityError,
    HarnessStore,
    LeaseError,
    ResourceSpec,
    StateError,
    TaskSpec,
)


def digest(value: bytes) -> str:
    return sha256(value).hexdigest()


class HarnessTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.path = Path(self.tmp.name) / "harness.db"
        self.store = HarnessStore(self.path)
        self.addCleanup(self.store.close)
        self.good = b"accepted-result"

    def task(self, **overrides):
        values = dict(
            task_id="task-1",
            intent_ref="intent-1",
            domain="test",
            capabilities=("python",),
            expected_result_sha256=digest(self.good),
            mutation_class="M1",
            cash_ceiling=0.0,
            context_budget=32,
            retry_budget=1,
        )
        values.update(overrides)
        return TaskSpec(**values)

    def resource(self, **overrides):
        values = dict(
            resource_id="local",
            capabilities=("python", "filesystem"),
            maximum_mutation_class="M1",
            hard_zero_spend_eligible=True,
            context_limit=64,
        )
        values.update(overrides)
        return ResourceSpec(**values)

    def seed(self):
        self.store.submit_task(self.task(), now=100)
        self.store.register_resource(self.resource(), now=100)

    def test_immutable_task_identity_is_idempotent_and_conflicts_fail(self):
        spec = self.task()
        first = self.store.submit_task(spec, now=100)
        self.assertEqual(first, self.store.submit_task(spec, now=101))
        with self.assertRaises(ConflictError):
            self.store.submit_task(self.task(domain="other"), now=102)
        with self.assertRaises(sqlite3.IntegrityError):
            self.store.cx.execute("UPDATE tasks SET spec_hash='x' WHERE task_id='task-1'")

    def test_resource_specs_are_immutable(self):
        self.store.register_resource(self.resource(), now=100)
        self.assertEqual(
            self.store.register_resource(self.resource(), now=101),
            self.store.register_resource(self.resource(), now=102),
        )
        with self.assertRaises(ConflictError):
            self.store.register_resource(self.resource(capabilities=("python",)), now=103)
        with self.assertRaises(sqlite3.IntegrityError):
            self.store.cx.execute("UPDATE resources SET spec_hash='x' WHERE resource_id='local'")

    def test_hard_zero_spend_and_capability_filtering(self):
        self.store.submit_task(self.task(), now=100)
        self.store.register_resource(self.resource(), now=100)
        self.store.register_resource(self.resource(resource_id="paid", hard_zero_spend_eligible=False), now=100)
        self.store.register_resource(self.resource(resource_id="weak", capabilities=("filesystem",)), now=100)
        self.store.register_resource(self.resource(resource_id="low-mutation", maximum_mutation_class="M0"), now=100)
        self.assertEqual(self.store.eligible_resources("task-1"), ["local"])
        with self.assertRaises(ValueError):
            self.task(cash_ceiling=0.01)

    def test_context_budget_is_enforced_before_lease(self):
        self.seed()
        with self.assertRaises(EligibilityError):
            self.store.acquire_lease("task-1", "local", b"x" * 33, ttl_seconds=10, now=100)
        self.assertEqual(self.store.task_state("task-1")["state"], "READY")

    def test_exclusive_task_and_resource_leases(self):
        self.seed()
        self.store.submit_task(self.task(task_id="task-2", intent_ref="intent-2"), now=100)
        self.store.acquire_lease("task-1", "local", b"ctx", ttl_seconds=10, now=100, lease_id="lease-1")
        other = HarnessStore(self.path)
        self.addCleanup(other.close)
        with self.assertRaises(LeaseError):
            other.acquire_lease("task-1", "local", b"ctx", ttl_seconds=10, now=101, lease_id="lease-2")
        with self.assertRaises(LeaseError):
            other.acquire_lease("task-2", "local", b"ctx", ttl_seconds=10, now=101, lease_id="lease-3")

    def test_expired_lease_recovers_to_ready_after_reopen(self):
        self.seed()
        self.store.acquire_lease("task-1", "local", b"ctx", ttl_seconds=5, now=100, lease_id="lease-1")
        self.store.close()
        self.store = HarnessStore(self.path)
        self.assertEqual(self.store.reap_expired(now=105), 1)
        self.assertEqual(self.store.task_state("task-1")["state"], "READY")
        lease = self.store.acquire_lease("task-1", "local", b"ctx", ttl_seconds=5, now=106, lease_id="lease-2")
        self.assertEqual(lease.lease_id, "lease-2")

    def test_digest_acceptance_and_transactional_canonical_commit(self):
        self.seed()
        self.store.acquire_lease("task-1", "local", b"ctx", ttl_seconds=10, now=100, lease_id="lease-1")
        attempt = self.store.record_attempt(
            "lease-1", result=self.good, result_ref="result://1", started_at=101, completed_at=102, attempt_id="attempt-1"
        )
        self.assertEqual(attempt.outcome, "ACCEPTED")
        self.assertEqual(self.store.task_state("task-1")["state"], "BLOCKED")
        receipt = self.store.commit_accepted("attempt-1", now=103)
        self.assertEqual(receipt["schema"], "axiom-harness/receipt-v1")
        self.assertEqual(receipt["result_digest"], digest(self.good))
        self.assertEqual(self.store.task_state("task-1")["state"], "COMMITTED")
        self.assertEqual(self.store.canonical_result("task-1"), receipt)
        self.assertEqual(self.store.commit_accepted("attempt-1", now=104), receipt)

    def test_canonical_commit_excludes_any_second_accepted_candidate(self):
        self.seed()
        self.store.acquire_lease("task-1", "local", b"ctx", ttl_seconds=10, now=100, lease_id="lease-1")
        self.store.record_attempt(
            "lease-1", result=self.good, started_at=101, completed_at=102, attempt_id="attempt-1"
        )
        with self.assertRaises(LeaseError):
            self.store.acquire_lease("task-1", "local", b"ctx", ttl_seconds=10, now=103, lease_id="lease-2")
        self.store.commit_accepted("attempt-1", now=104)
        self.assertEqual(len(self.store.attempts("task-1")), 1)

    def test_accepted_candidate_survives_restart_before_commit(self):
        self.seed()
        self.store.acquire_lease("task-1", "local", b"ctx", ttl_seconds=10, now=100, lease_id="lease-1")
        self.store.record_attempt(
            "lease-1", result=self.good, started_at=101, completed_at=102, attempt_id="attempt-1"
        )
        self.store.close()
        self.store = HarnessStore(self.path)
        self.assertEqual(self.store.task_state("task-1")["state"], "BLOCKED")
        self.assertEqual(self.store.commit_accepted("attempt-1", now=103)["outcome"], "ACCEPTED")

    def test_commit_failure_rolls_back_without_losing_accepted_candidate(self):
        self.seed()
        self.store.acquire_lease("task-1", "local", b"ctx", ttl_seconds=10, now=100, lease_id="lease-1")
        self.store.record_attempt(
            "lease-1", result=self.good, started_at=101, completed_at=102, attempt_id="attempt-1"
        )
        self.store.cx.execute(
            "CREATE TRIGGER fail_commit BEFORE INSERT ON canonical_results BEGIN SELECT RAISE(ABORT,'fault'); END"
        )
        with self.assertRaises(sqlite3.IntegrityError):
            self.store.commit_accepted("attempt-1", now=103)
        self.assertIsNone(self.store.canonical_result("task-1"))
        self.assertEqual(self.store.task_state("task-1")["state"], "BLOCKED")

    def test_unknown_is_explicit_and_never_automatically_retryable(self):
        self.seed()
        self.store.acquire_lease("task-1", "local", b"ctx", ttl_seconds=10, now=100, lease_id="lease-1")
        attempt = self.store.record_attempt(
            "lease-1", failure="unknown", started_at=101, completed_at=102, attempt_id="attempt-1"
        )
        self.assertEqual(attempt.outcome, "UNKNOWN")
        self.assertFalse(attempt.retry_safe)
        self.assertEqual(self.store.task_state("task-1")["state"], "UNKNOWN")
        with self.assertRaises(LeaseError):
            self.store.acquire_lease("task-1", "local", b"ctx", ttl_seconds=10, now=103)
        with self.assertRaises(ValueError):
            self.store.record_attempt("missing", failure="unknown", retry_safe=True)

    def test_retry_requires_positive_safety_and_respects_budget(self):
        self.seed()
        self.store.acquire_lease("task-1", "local", b"ctx", ttl_seconds=10, now=100, lease_id="lease-1")
        first = self.store.record_attempt(
            "lease-1", result=b"wrong", retry_safe=True, started_at=101, completed_at=102, attempt_id="attempt-1"
        )
        self.assertEqual(first.outcome, "REJECTED")
        self.assertEqual(self.store.task_state("task-1")["state"], "READY")
        self.store.acquire_lease("task-1", "local", b"ctx", ttl_seconds=10, now=103, lease_id="lease-2")
        second = self.store.record_attempt(
            "lease-2", result=b"wrong-again", retry_safe=True, started_at=104, completed_at=105, attempt_id="attempt-2"
        )
        self.assertEqual(second.outcome, "REJECTED")
        self.assertEqual(self.store.task_state("task-1")["state"], "FAILED")
        self.assertEqual(len(self.store.attempts("task-1")), 2)

    def test_rejected_without_retry_safety_fails_closed(self):
        self.seed()
        self.store.acquire_lease("task-1", "local", b"ctx", ttl_seconds=10, now=100, lease_id="lease-1")
        self.store.record_attempt(
            "lease-1", result=b"wrong", retry_safe=False, started_at=101, completed_at=102, attempt_id="attempt-1"
        )
        self.assertEqual(self.store.task_state("task-1")["state"], "FAILED")

    def test_attempt_rows_are_immutable(self):
        self.seed()
        self.store.acquire_lease("task-1", "local", b"ctx", ttl_seconds=10, now=100, lease_id="lease-1")
        self.store.record_attempt(
            "lease-1", failure="failed", retry_safe=False, started_at=101, completed_at=102, attempt_id="attempt-1"
        )
        with self.assertRaises(sqlite3.IntegrityError):
            self.store.cx.execute("UPDATE attempts SET outcome='ACCEPTED' WHERE attempt_id='attempt-1'")
        with self.assertRaises(sqlite3.IntegrityError):
            self.store.cx.execute("DELETE FROM attempts WHERE attempt_id='attempt-1'")

    def test_check_survives_reopen(self):
        self.seed()
        self.assertEqual(self.store.check(), {"ok": True, "schema_version": 1})
        self.store.close()
        self.store = HarnessStore(self.path)
        self.assertEqual(self.store.check(), {"ok": True, "schema_version": 1})


if __name__ == "__main__":
    unittest.main()
