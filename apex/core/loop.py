"""Main execution loop — pure function over State."""
import json
import signal
import sys
from contextlib import contextmanager
from dataclasses import replace
from time import time, sleep as _sleep

from apex.config import Config
from apex.core.state import State, create_initial_state
from apex.core.planner import generate_plan
from apex.core.types import Halt, ToolCall, ToolExecution, Ok, Err
from apex.core.trace import write_event
from apex.history import record_run
from apex.paranoid import audit_plan, format_audit_report

_MAX_OUTPUT_BYTES = 10_485_760  # 10 MB
_TOOL_TIMEOUT_S = 300
_MAX_RETRIES = 3
_RETRY_DELAY_S = 2


class ApexTimeoutError(Exception):
    pass


@contextmanager
def _timeout(seconds: int):
    def _handler(signum, frame):
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


def _ftrace(config: Config, event: dict) -> None:
    if config.full_trace:
        write_event(event, dest=config.trace_path)


def run(input_str: str, config: Config, registry: dict) -> State:
    state = create_initial_state(input_str)
    _wall_start = time()

    if config.dry_run:
        state = generate_plan(state, config, registry)
        if state.plan:
            steps = [
                {"type": "halt", "reason": s.reason}
                if isinstance(s, Halt)
                else {"type": "tool", "name": s.name, "args": s.args}
                for s in state.plan.steps
            ]
            print(json.dumps({"goal": state.plan.goal, "steps": steps}, indent=2))
        return _finish(replace(state, status="HALTED"))

    state = generate_plan(state, config, registry)
    _trace(config, f"[plan] goal={state.plan.goal if state.plan else 'NONE'} status={state.status}")
    _ftrace(config, {"event": "plan", "goal": state.plan.goal if state.plan else None, "steps": len(state.plan.steps) if state.plan else 0, "status": state.status})

    if config.paranoid and state.plan:
        try:
            audit = audit_plan(state.plan, api_key=config.api_key)
            _trace(config, format_audit_report(audit))
            _ftrace(config, {"event": "paranoid_audit", "result": audit})
            if not audit.get("safe", True):
                print(format_audit_report(audit), flush=True)
                return _finish(replace(state, status="ERROR"))
        except Exception as e:
            _trace(config, f"[paranoid] audit failed: {e}")
            return replace(state, status="ERROR")
    if state.status != "RUNNING":
        return state

    def _finish(st):
        record_run(
            task=input_str,
            plan=st.plan.steps if st.plan else None,
            exit_code=0 if st.status == 'HALTED' else 1,
            token_count=st.token_count or 0,
            wall_seconds=round(time() - _wall_start, 3),
        )
        return st

    while state.status == "RUNNING" and state.plan and state.plan.steps:
        step = state.plan.steps[0]

        if isinstance(step, Halt):
            _trace(config, f"[halt] {step.reason}")
            _ftrace(config, {"event": "halt", "reason": step.reason})
            return _finish(replace(state, status="HALTED"))

        if isinstance(step, ToolCall):
            tool = registry[step.name]
            _trace(config, f"[tool] {step.name} args={step.args}")
            _ftrace(config, {"event": "tool_call", "tool": step.name, "args": step.args})

            result = None
            for _attempt in range(1, _MAX_RETRIES + 1):
                try:
                    with _timeout(_TOOL_TIMEOUT_S):
                        output = tool.effect(step.args)
                    if len(str(output)) > _MAX_OUTPUT_BYTES:
                        result = Err("ToolOutputError", f"{step.name} output exceeds 10 MB")
                        break  # non-retryable
                    else:
                        result = Ok(output if isinstance(output, dict) else {"output": output})
                        break
                except ApexTimeoutError:
                    result = Err("ToolTimeout", f"{step.name} exceeded {_TOOL_TIMEOUT_S}s")
                except Exception as e:
                    result = Err("ToolExecutionError", str(e))
                if _attempt < _MAX_RETRIES:
                    _ftrace(config, {"event": "tool_retry", "tool": step.name, "attempt": _attempt, "reason": result.message})
                    _trace(config, f"[retry] {step.name} attempt {_attempt}/{_MAX_RETRIES}: {result.message}")
                    _sleep(_RETRY_DELAY_S * _attempt)

            _trace(config, f"[result] {'ok' if isinstance(result, Ok) else 'err: ' + result.message}")
            _ftrace(config, {"event": "tool_result", "tool": step.name, "status": "ok" if isinstance(result, Ok) else "err", "output": result.value if isinstance(result, Ok) else result.message})

            state = replace(
                state,
                plan=replace(state.plan, steps=state.plan.steps[1:]),
                history=state.history + (ToolExecution(step.name, step.args, result, time()),),
            )

            if isinstance(result, Err):
                return _finish(replace(state, status="ERROR"))

    _ftrace(config, {"event": "run_complete", "status": "HALTED", "tokens": state.token_count})
    return _finish(replace(state, status="HALTED"))
