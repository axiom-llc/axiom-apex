"""State management for APEX"""
from dataclasses import dataclass, replace
from typing import Literal
from core.types import Plan, Event

@dataclass(frozen=True)
class State:
    input: str
    plan: Plan | None
    memory: tuple[dict, ...]
    history: tuple[Event, ...]
    status: Literal["RUNNING", "HALTED", "ERROR"]
    token_count: int

def create_initial_state(input_str: str) -> State:
    return State(
        input=input_str,
        plan=None,
        memory=(),
        history=(),
        status="RUNNING",
        token_count=0
    )

def format_output(state: State) -> str:
    lines = [f"Status: {state.status}"]
    lines.append(f"Tokens: {state.token_count}")
    
    if state.plan:
        lines.append(f"\nGoal: {state.plan.goal}")
        lines.append(f"Steps executed: {len([e for e in state.history if hasattr(e, 'tool')])}")
    
    for event in state.history:
        if hasattr(event, 'tool'):
            lines.append(f"\n[{event.tool}]")
            if hasattr(event.result, 'value'):
                lines.append(f"  Success: {event.result.value}")
            else:
                lines.append(f"  Error: {event.result.message}")
        elif hasattr(event, 'error_type'):
            lines.append(f"\nError: {event.message}")
    
    return '\n'.join(lines)
