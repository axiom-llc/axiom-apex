import asyncio
import unittest

from team import Task, Worker, coordinate


async def add(task, inputs, feedback):
    await asyncio.sleep(task.delay)
    return task.value + sum(inputs.values())


def valid(task, result):
    return None if type(result) is int else "return an integer"


class TeamTests(unittest.IsolatedAsyncioTestCase):
    async def test_dependencies_pass_only_accepted_results(self):
        tasks = [Task("a", value=2), Task("b", value=3), Task("c", deps=("a", "b"), value=1)]
        report = await coordinate(tasks, [Worker("w", add)], valid)
        self.assertEqual(report.results, {"a": 2, "b": 3, "c": 6})
        self.assertEqual(report.states, {t.id: "accepted" for t in tasks})

    async def test_idle_worker_takes_next_task_before_slow_peer_finishes(self):
        started = asyncio.Event()
        release = asyncio.Event()

        async def work(task, inputs, feedback):
            if task.id == "slow":
                await release.wait()
            elif task.id == "third":
                started.set()
            return 1

        run = asyncio.create_task(coordinate(
            [Task("slow"), Task("fast"), Task("third")],
            [Worker("a", work), Worker("b", work)], valid))
        try:
            await asyncio.wait_for(started.wait(), 1)
        finally:
            release.set()
        self.assertEqual(len((await run).results), 3)

    async def test_validation_feedback_allows_one_pure_correction(self):
        seen = []

        async def work(task, inputs, feedback):
            seen.append(feedback)
            return "bad" if feedback is None else 7

        report = await coordinate([Task("x", correction_safe=True)], [Worker("w", work)], valid)
        self.assertEqual(seen, [None, "return an integer"])
        self.assertEqual(report.results, {"x": 7})

    async def test_correction_is_bounded(self):
        async def bad(*args):
            return "bad"
        report = await coordinate([Task("x", correction_safe=True)], [Worker("w", bad)], valid)
        self.assertEqual(report.states["x"], "rejected")
        self.assertEqual(len(report.attempts), 2)

    async def test_exception_is_unknown_and_blocks_dependents_without_retry(self):
        async def fail(*args):
            raise RuntimeError("uncertain")
        report = await coordinate([Task("x", correction_safe=True), Task("y", deps=("x",))],
                                  [Worker("w", fail)], valid)
        self.assertEqual(report.states, {"x": "unknown", "y": "blocked"})
        self.assertEqual(len(report.attempts), 1)

    async def test_timeout_is_unknown(self):
        async def slow(*args):
            await asyncio.sleep(1)
        report = await coordinate([Task("x", timeout=.001)], [Worker("w", slow)], valid)
        self.assertEqual(report.states["x"], "unknown")

    async def test_capabilities_and_fastest_idle_worker(self):
        tasks = [Task("x", capability="review")]
        report = await coordinate(tasks, [Worker("wrong", add),
            Worker("slow", add, capabilities=("review",), speed=1),
            Worker("fast", add, capabilities=("review",), speed=2)], valid)
        self.assertEqual(report.attempts[0]["worker"], "fast")

    async def test_no_capable_worker_rejected_before_dispatch(self):
        with self.assertRaises(ValueError):
            await coordinate([Task("x", capability="missing")], [Worker("w", add)], valid)

    async def test_invalid_graphs_rejected_before_dispatch(self):
        graphs = [[Task("x"), Task("x")], [Task("x", deps=("missing",))],
                  [Task("x", deps=("y",)), Task("y", deps=("x",))]]
        for tasks in graphs:
            with self.subTest(tasks=tasks), self.assertRaises(ValueError):
                await coordinate(tasks, [Worker("w", add)], valid)

    async def test_invalid_worker_and_limits_rejected(self):
        for workers in [[], [Worker("w", add), Worker("w", add)], [Worker("w", add, speed=0)]]:
            with self.subTest(workers=workers), self.assertRaises(ValueError):
                await coordinate([Task("x")], workers, valid)
        for task in [Task("x", timeout=0), Task("x", delay=-1), Task("x", delay=float("nan"))]:
            with self.subTest(task=task), self.assertRaises(ValueError):
                await coordinate([task], [Worker("w", add)], valid)

    async def test_rejection_blocks_children_but_independent_work_finishes(self):
        def reject(task, result):
            return "no" if task.id == "x" else None
        report = await coordinate([Task("x"), Task("y", deps=("x",)), Task("z")],
                                  [Worker("w", add)], reject)
        self.assertEqual(report.states, {"x": "rejected", "y": "blocked", "z": "accepted"})

    async def test_cancellation_drains_active_callbacks(self):
        entered = asyncio.Event()
        exited = asyncio.Event()
        async def work(*args):
            entered.set()
            try:
                await asyncio.Event().wait()
            finally:
                exited.set()
        run = asyncio.create_task(coordinate([Task("x")], [Worker("w", work)], valid))
        await entered.wait()
        run.cancel()
        with self.assertRaises(asyncio.CancelledError):
            await run
        self.assertTrue(exited.is_set())

    async def test_all_policies_preserve_dependency_results(self):
        tasks = [Task("a", value=2), Task("b", deps=("a",), value=3)]
        for policy in ("serial", "batch", "dynamic"):
            report = await coordinate(tasks, [Worker("w", add)], valid, policy=policy)
            self.assertEqual(report.results["b"], 5)

    async def test_mutable_inputs_and_results_are_isolated(self):
        async def mutate(task, inputs, feedback):
            if task.id == "a":
                return {"items": [1]}
            inputs["a"]["items"].append(2)
            return inputs["a"]
        report = await coordinate([Task("a"), Task("b", deps=("a",)), Task("c", deps=("a",))],
                                  [Worker("w", mutate)], lambda t, r: None)
        self.assertEqual(report.results["a"], {"items": [1]})
        self.assertEqual(report.results["c"], {"items": [1, 2]})

    async def test_payload_bound_and_non_json_rejected(self):
        async def bad(*args):
            return float("nan")
        report = await coordinate([Task("a")], [Worker("w", bad)], valid)
        self.assertEqual(report.states["a"], "rejected")

    async def test_instruction_is_delivered_and_bounded_before_dispatch(self):
        async def read(task, inputs, feedback):
            return task.instruction
        report = await coordinate([Task("a", instruction="review this candidate")],
                                  [Worker("w", read)], lambda t, r: None)
        self.assertEqual(report.results["a"], "review this candidate")
        with self.assertRaises(ValueError):
            await coordinate([Task("a", instruction="x" * 20)],
                             [Worker("w", read)], valid, max_bytes=10)

    async def test_validation_error_is_unknown_and_unsafe_correction_disabled(self):
        def broken(task, result):
            raise RuntimeError("validator failed")
        report = await coordinate([Task("a", correction_safe=True)], [Worker("w", add)], broken)
        self.assertEqual(report.states["a"], "unknown")
        self.assertEqual(len(report.attempts), 1)
        async def wrong(*args):
            return "bad"
        report = await coordinate([Task("a")], [Worker("w", wrong)], valid)
        self.assertEqual(report.states["a"], "rejected")
        self.assertEqual(len(report.attempts), 1)
        async def large(*args):
            return "x" * 100
        report = await coordinate([Task("a")], [Worker("w", large)], valid, max_bytes=10)
        self.assertEqual(report.states["a"], "rejected")


if __name__ == "__main__":
    unittest.main()
