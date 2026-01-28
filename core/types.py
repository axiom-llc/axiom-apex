"""Core type definitions for APEX"""
from dataclasses import dataclass
from typing import Any, Callable, Literal

@dataclass(frozen=True)
class ToolCall:
    name: str
    args: dict[str, Any]

@dataclass(frozen=True)
class Halt:
    reason: str

Step = ToolCall | Halt

@dataclass(frozen=True)
class Plan:
    goal: str
    steps: tuple[Step, ...]

@dataclass(frozen=True)
class PlanGeneration:
    tokens: int
    timestamp: float

@dataclass(frozen=True)
class ToolExecution:
    tool: str
    args: dict[str, Any]
    result: 'Result'
    timestamp: float

@dataclass(frozen=True)
class ErrorEvent:
    error_type: str
    message: str
    timestamp: float

Event = PlanGeneration | ToolExecution | ErrorEvent

@dataclass(frozen=True)
class Ok:
    value: dict[str, Any]

@dataclass(frozen=True)
class Err:
    error_type: str
    message: str

Result = Ok | Err

@dataclass(frozen=True)
class Tool:
    name: str
    input_spec: dict[str, type]
    output_spec: dict[str, type]
    effect: Callable[[dict], Result]
