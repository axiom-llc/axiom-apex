"""Evaluation-only bounded teams. No provider, APEX, network or durable-state adapter."""
from __future__ import annotations

import asyncio
import json
import math
from dataclasses import dataclass, field
from time import perf_counter
from typing import Any, Awaitable, Callable


@dataclass(frozen=True)
class Task:
    id: str
    instruction: str = ""
    deps: tuple[str, ...] = ()
    capability: str = "general"
    value: int = 0
    delay: float = 0
    timeout: float = 5
    correction_safe: bool = False


Agent = Callable[[Task, dict[str, Any], str | None], Awaitable[Any]]
Validator = Callable[[Task, Any], str | None]


@dataclass(frozen=True)
class Worker:
    id: str
    agent: Agent
    capabilities: tuple[str, ...] = ("general",)
    speed: float = 1


@dataclass
class Report:
    states: dict[str, str]
    results: dict[str, Any] = field(default_factory=dict)
    attempts: list[dict] = field(default_factory=list)
    elapsed: float = 0


def _copy_json(value: Any, max_bytes: int) -> Any:
    raw = json.dumps(value, allow_nan=False, separators=(",", ":"))
    if len(raw.encode("utf-8")) > max_bytes:
        raise ValueError("payload limit")
    return json.loads(raw)


def _check(tasks, workers, policy, max_bytes):
    if policy not in {"serial", "batch", "dynamic"}:
        raise ValueError("unknown policy")
    if not 0 < len(tasks) <= 64 or not 0 < len(workers) <= 8 or max_bytes <= 0:
        raise ValueError("limits: 1..64 tasks, 1..8 workers, positive payload bound")
    ids = [t.id for t in tasks]
    if len(set(ids)) != len(ids) or any(not i for i in ids):
        raise ValueError("unique nonempty task IDs required")
    if len({w.id for w in workers}) != len(workers):
        raise ValueError("unique worker IDs required")
    for w in workers:
        if not w.id or not callable(w.agent) or not math.isfinite(w.speed) or w.speed <= 0:
            raise ValueError("invalid worker")
    known = set(ids)
    for t in tasks:
        if not isinstance(t.instruction, str):
            raise ValueError("instruction must be text")
        _copy_json(t.instruction, max_bytes)
        if (not math.isfinite(t.timeout) or t.timeout <= 0 or
                not math.isfinite(t.delay) or t.delay < 0 or
                len(set(t.deps)) != len(t.deps) or not set(t.deps) <= known):
            raise ValueError("invalid task")
        if not any(t.capability in w.capabilities for w in workers):
            raise ValueError("no eligible worker")
    resolved = set()
    while len(resolved) < len(tasks):
        ready = {t.id for t in tasks if set(t.deps) <= resolved} - resolved
        if not ready:
            raise ValueError("dependency cycle")
        resolved.update(ready)


async def coordinate(tasks: list[Task], workers: list[Worker], validator: Validator,
                     *, policy: str = "dynamic", max_bytes: int = 65536) -> Report:
    """Advance a fixed graph autonomously; validate before downstream release.

    Callbacks are trusted cooperative coroutines. Speed is a caller-supplied
    relative throughput hint, not a learned/provider performance guarantee.
    Validation corrections require explicit pure/repeat-safe task authorization.
    Exceptions and timeouts are UNKNOWN and never retried.
    """
    start = perf_counter()
    tasks, workers = tuple(tasks), tuple(workers)
    _check(tasks, workers, policy, max_bytes)
    report = Report({t.id: "pending" for t in tasks})
    active: dict[asyncio.Task, tuple[Task, Worker]] = {}

    async def execute(task, worker, inputs):
        feedback = None
        for number in range(1, 3 if task.correction_safe else 2):
            began = perf_counter()
            status = "unknown"
            try:
                result = await asyncio.wait_for(
                    worker.agent(task, _copy_json(inputs, max_bytes), feedback), task.timeout)
            except Exception:
                report.attempts.append(dict(task=task.id, worker=worker.id,
                    attempt=number, state=status, seconds=perf_counter() - began))
                return status, None
            try:
                result = _copy_json(result, max_bytes)
            except (TypeError, ValueError, OverflowError, RecursionError):
                feedback = "return a finite JSON result within the payload limit"
            else:
                try:
                    feedback = validator(task, _copy_json(result, max_bytes))
                    if feedback is not None:
                        if not isinstance(feedback, str):
                            raise ValueError("validator must return None or a string")
                        feedback = _copy_json(feedback, max_bytes)
                except Exception:
                    report.attempts.append(dict(task=task.id, worker=worker.id,
                        attempt=number, state="unknown", seconds=perf_counter() - began))
                    return "unknown", None
                if feedback is None:
                    status = "accepted"
            if feedback is not None:
                status = "rejected"
            report.attempts.append(dict(task=task.id, worker=worker.id,
                attempt=number, state=status, seconds=perf_counter() - began))
            if status == "accepted":
                return status, result
        return "rejected", None

    try:
        while any(s in {"pending", "running"} for s in report.states.values()):
            # Propagate blocked dependencies to a fixed point before dispatch.
            changed = True
            while changed:
                changed = False
                for task in tasks:
                    if report.states[task.id] == "pending" and any(
                            report.states[d] in {"unknown", "rejected", "blocked"} for d in task.deps):
                        report.states[task.id] = "blocked"
                        changed = True
            busy = {w.id for _, w in active.values()}
            if policy == "dynamic" or not active:
                for task in tasks:
                    if report.states[task.id] != "pending" or not all(
                            report.states[d] == "accepted" for d in task.deps):
                        continue
                    available = [w for w in workers if w.id not in busy and
                                 task.capability in w.capabilities]
                    if not available or (policy == "serial" and active):
                        continue
                    worker = min(available, key=lambda w: (-w.speed, w.id))
                    inputs = {d: report.results[d] for d in task.deps}
                    try:
                        inputs = _copy_json(inputs, max_bytes)
                    except (TypeError, ValueError, OverflowError, RecursionError):
                        report.states[task.id] = "rejected"
                        continue
                    report.states[task.id] = "running"
                    future = asyncio.create_task(execute(task, worker, inputs))
                    active[future] = (task, worker)
                    busy.add(worker.id)
            if not active:
                if any(s == "pending" for s in report.states.values()):
                    continue  # propagate an oversized-input rejection
                break
            done, _ = await asyncio.wait(active, return_when=(
                asyncio.ALL_COMPLETED if policy == "batch" else asyncio.FIRST_COMPLETED))
            for future in sorted(done, key=lambda f: active[f][0].id):
                task, _ = active.pop(future)
                state, result = future.result()
                report.states[task.id] = state
                if state == "accepted":
                    report.results[task.id] = result
    finally:
        for future in active:
            future.cancel()
        if active:
            await asyncio.gather(*active, return_exceptions=True)
        report.elapsed = perf_counter() - start
    return report
