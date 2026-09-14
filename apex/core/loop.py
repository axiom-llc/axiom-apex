"""Bounded plan generation and tool execution."""
import json
import signal
import sys
from contextlib import contextmanager
from copy import deepcopy
from dataclasses import replace
from time import sleep, time

from apex.config import Config
from apex.core.planner import generate_plan, parse_plan
from apex.core.state import State, create_initial_state
from apex.core.trace import write_event
from apex.core.types import Err, ErrorEvent, Halt, Ok, Plan, Tool, ToolCall, ToolExecution, plan_to_dict
from apex.history import (RecoveryBlocked, begin_run, bound_effects, dispatch_effect,
                          finish_run, observe_effect, record_run)
from apex.safety import audit_plan, format_audit_report

_MAX_OUTPUT_BYTES = 10_485_760
_TOOL_TIMEOUT_S = 300
_MAX_RETRIES = 3
_RETRY_DELAY_S = 2


class ApexTimeoutError(Exception):
    pass


@contextmanager
def _timeout(seconds: int):
    def _handler(signum, frame):
        del signum, frame
        raise ApexTimeoutError()

    old = signal.signal(signal.SIGALRM, _handler)
    signal.alarm(seconds)
    try:
        yield
    finally:
        signal.alarm(0)
        signal.signal(signal.SIGALRM, old)


def _trace(config: Config, message: str) -> None:
    if config.trace:
        print(message, file=sys.stderr)


def _full_trace(config: Config, event: dict) -> None:
    if config.full_trace:
        write_event(event, dest=config.trace_path)


def _finish(
    state: State,
    *,
    task: str,
    wall_start: float,
    events: list[dict],
) -> State:
    if state.run_id is not None:
        finish_run(state.run_id, 0 if state.status == "HALTED" else 1, round(time() - wall_start, 3))
        return state
    run_id = record_run(
        task=task,
        plan=plan_to_dict(state.plan) if state.plan else None,
        exit_code=0 if state.status == "HALTED" else 1,
        token_count=state.token_count,
        wall_seconds=round(time() - wall_start, 3),
        events=events,
    )
    return replace(state, run_id=run_id)


def _audit(state: State, config: Config) -> State:
    if not config.audit or state.plan is None:
        return state
    try:
        audit = audit_plan(state.plan, api_key=config.api_key)
        report = format_audit_report(audit)
        _trace(config, report)
        _full_trace(config, {"event": "plan_audit", "result": audit})
        if not audit["safe"]:
            print(report, file=sys.stderr)
            return replace(state, status="ERROR")
        return state
    except Exception as exc:
        _trace(config, f"[audit] failed: {exc}")
        return replace(state, status="ERROR")


def _normalize_output(tool_name: str, output) -> Ok | Err:
    value = output if isinstance(output, dict) else {"output": output}
    try:
        encoded = json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    except (TypeError, ValueError) as exc:
        return Err("ToolOutputError", f"{tool_name} returned non-JSON output: {exc}")
    if len(encoded) > _MAX_OUTPUT_BYTES:
        return Err("ToolOutputError", f"{tool_name} output exceeds 10 MiB")
    return Ok(value)


def _execute(state: State, config: Config, registry: dict[str, Tool], events: list[dict],
             authorization: dict | None = None) -> State:
    if state.status != "RUNNING" or state.plan is None:
        return state

    if state.run_id is None:
        raise RecoveryBlocked("execution requires a durable run binding")
    effects = {
        row["step"]: row
        for row in bound_effects(
            state.run_id, plan_to_dict(state.plan), authorization=authorization
        )
    }
    for row in effects.values():
        if row["state"] not in {"INTENT_RECORDED", "SUCCEEDED"}:
            raise RecoveryBlocked(
                f"run {state.run_id} step {row['step']}: {row['state']} has an uncertain effect outcome; recovery blocked"
            )

    for step_index, step in enumerate(state.plan.steps):
        if isinstance(step, Halt):
            _trace(config, f"[halt] {step.reason}")
            _full_trace(config, {"event": "halt", "reason": step.reason})
            _full_trace(
                config,
                {"event": "run_complete", "status": "HALTED", "tokens": state.token_count},
            )
            return replace(state, status="HALTED")

        if not isinstance(step, ToolCall):
            return replace(state, status="ERROR")

        recorded = effects[step_index]
        if recorded["state"] == "SUCCEEDED":
            result = Ok(json.loads(recorded["result_json"]))
            state = replace(state, history=state.history + (
                ToolExecution(step.name, step.args, result, time()),
            ))
            continue

        tool = registry[step.name]
        _trace(config, f"[tool] {step.name} args={step.args}")
        _full_trace(config, {"event": "tool_call", "tool": step.name, "args": step.args})

        result: Ok | Err
        max_attempts = _MAX_RETRIES if tool.retry_safe else 1
        dispatch_effect(state.run_id, step_index)
        for attempt in range(1, max_attempts + 1):
            try:
                with _timeout(_TOOL_TIMEOUT_S):
                    output = tool.effect(deepcopy(step.args))
                result = _normalize_output(step.name, output)
                break
            except ApexTimeoutError:
                result = Err("ToolTimeout", f"{step.name} exceeded {_TOOL_TIMEOUT_S}s")
            except Exception as exc:
                result = Err("ToolExecutionError", str(exc))

            if attempt < max_attempts:
                observe_effect(state.run_id, {
                    "step": step_index, "tool": step.name, "args": step.args,
                    "result": {"error": result.message},
                }, succeeded=False, retrying=True)
                _full_trace(
                    config,
                    {
                        "event": "tool_retry",
                        "tool": step.name,
                        "attempt": attempt,
                        "reason": result.message,
                    },
                )
                _trace(
                    config,
                    f"[retry] {step.name} attempt {attempt}/{max_attempts}: {result.message}",
                )
                sleep(_RETRY_DELAY_S * attempt)

        event_result = result.value if isinstance(result, Ok) else {"error": result.message}
        event = {"step": step_index, "tool": step.name, "args": step.args, "result": event_result}
        observe_effect(state.run_id, event, succeeded=isinstance(result, Ok))
        _trace(
            config,
            f"[result] {'ok' if isinstance(result, Ok) else 'err: ' + result.message}",
        )
        events.append(event)
        _full_trace(
            config,
            {
                "event": "tool_result",
                "tool": step.name,
                "status": "ok" if isinstance(result, Ok) else "err",
                "output": result.value if isinstance(result, Ok) else result.message,
            },
        )
        state = replace(
            state,
            history=state.history + (ToolExecution(step.name, step.args, result, time()),),
        )
        if isinstance(result, Err):
            return replace(state, status="ERROR")

    return replace(state, status="ERROR")


def _run_prepared(task: str, state: State, config: Config, registry: dict[str, Tool],
                  *, wall_start: float | None = None,
                  authorization: dict | None = None) -> State:
    wall_start = time() if wall_start is None else wall_start
    events: list[dict] = []
    _trace(
        config,
        f"[plan] goal={state.plan.goal if state.plan else 'NONE'} status={state.status}",
    )
    _full_trace(
        config,
        {
            "event": "plan",
            "goal": state.plan.goal if state.plan else None,
            "steps": len(state.plan.steps) if state.plan else 0,
            "status": state.status,
        },
    )
    if state.status == "RUNNING" and state.plan is not None:
        # Snapshot nested arguments and validate even direct Python callers.
        parsed = parse_plan(json.dumps(plan_to_dict(state.plan), allow_nan=False), registry)
        if isinstance(parsed, Err):
            return replace(state, status="ERROR", history=state.history + (
                ErrorEvent(parsed.error_type, parsed.message, time()),
            ))
        state = replace(state, plan=parsed)
    if state.run_id is None:
        state = _audit(state, config)
    try:
        if state.run_id is None and state.status == "RUNNING" and state.plan is not None:
            state = replace(
                state,
                run_id=begin_run(
                    task,
                    plan_to_dict(state.plan),
                    state.token_count,
                    authorization=authorization,
                ),
            )
        state = _execute(state, config, registry, events, authorization=authorization)
    except RecoveryBlocked as exc:
        return replace(state, status="ERROR", history=state.history + (
            ErrorEvent("RecoveryBlocked", str(exc), time()),
        ))
    return _finish(state, task=task, wall_start=wall_start, events=events)


def run(input_str: str, config: Config, registry: dict[str, Tool]) -> State:
    """Generate, validate, execute, trace, and record a plan for input_str."""
    wall_start = time()
    state = generate_plan(create_initial_state(input_str), config, registry)

    if config.dry_run:
        if state.plan:
            print(json.dumps(plan_to_dict(state.plan), indent=2))
            state = replace(state, status="HALTED")
        return _finish(state, task=input_str, wall_start=wall_start, events=[])

    return _run_prepared(input_str, state, config, registry, wall_start=wall_start)


def run_plan(input_str: str, plan: Plan, config: Config, registry: dict[str, Tool],
             *, run_id: int | None = None,
             authorization: dict | None = None) -> State:
    """Execute an exact plan, or recover its existing durable run without replanning."""
    state = replace(create_initial_state(input_str), plan=plan, run_id=run_id)
    return _run_prepared(
        input_str, state, config, registry, authorization=authorization
    )
