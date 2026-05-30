"""Plan generation and parsing."""
import json
import os
from dataclasses import replace
from importlib import resources
from time import time

from apex.config import Config
from apex.core.state import State
from apex.core.types import Err, ErrorEvent, Halt, Plan, PlanGeneration, ToolCall, Tool
from apex.llm import gemini_complete


def _load_prompt() -> str:
    return resources.files("apex").joinpath("prompt.txt").read_text(encoding="utf-8")


def render_prompt(task: str, registry: dict[str, Tool]) -> str:
    task = task.replace("~", os.path.expanduser("~"))
    tools_desc = "\n".join(
        f"- {name}: {tool.input_spec} -> {tool.output_spec}"
        for name, tool in registry.items()
    )
    return (
        f"{_load_prompt()}\n\n"
        f"Available tools:\n{tools_desc}\n\n"
        f"Task: {task}\n\n"
        f"Provide plan in JSON format."
    )


def parse_plan(response_text: str, registry: dict) -> Plan | Err:
    """Parse and validate plan JSON against the tool registry."""
    try:
        text = response_text
        if "```" in text:
            start = text.find("```")
            inner_start = text.find("\n", start) + 1
            end = text.find("```", inner_start)
            text = text[inner_start:end].strip()
        else:
            start = text.find("{")
            end = text.rfind("}") + 1
            if start == -1 or end == 0:
                return Err("ParseError", "No JSON object found in response")
            text = text[start:end]

        data = json.loads(text)

        if "goal" not in data or "steps" not in data:
            return Err("ParseError", "Missing required fields: goal, steps")

        if len(data["steps"]) > 32:
            return Err("ValidationError", f"Plan has {len(data['steps'])} steps; maximum is 32")

        steps: list[Halt | ToolCall] = []
        for i, raw in enumerate(data["steps"]):
            step_type = str(raw.get("type", "")).lower()
            if step_type == "halt":
                steps.append(Halt(reason=raw.get("reason", "Complete")))
            elif step_type in ("tool", "toolcall"):
                name = raw.get("name")
                if name not in registry:
                    return Err("ValidationError", f"Step {i}: unknown tool '{name}'")
                steps.append(ToolCall(name=name, args=raw.get("args", {})))
            else:
                return Err("ParseError", f"Step {i}: invalid type '{step_type}'")

        return Plan(goal=data["goal"], steps=tuple(steps))

    except json.JSONDecodeError as e:
        return Err("ParseError", f"Invalid JSON: {e}")
    except Exception as e:
        return Err("ParseError", str(e))


def generate_plan(state: State, config: Config, registry: dict) -> State:
    prompt = render_prompt(state.input, registry)
    response = gemini_complete(prompt, api_key=config.api_key)
    result = parse_plan(response["text"], registry)

    if isinstance(result, Plan):
        return replace(
            state,
            plan=result,
            history=state.history + (PlanGeneration(response["tokens"], time()),),
            token_count=state.token_count + response["tokens"],
        )

    return replace(
        state,
        status="ERROR",
        history=state.history + (ErrorEvent(result.error_type, result.message, time()),),
    )
