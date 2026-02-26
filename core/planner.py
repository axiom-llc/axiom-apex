"""Plan generation and parsing"""
import os
import sys
import json
from dataclasses import replace
from time import time
from core.types import Plan, Step, ToolCall, Halt, Ok, Err, PlanGeneration, ErrorEvent
from core.state import State
from llm.providers import gemini_complete
from tools.registry import REGISTRY

def render_prompt(task: str, memory: tuple[dict, ...]) -> str:
    # Expand ~ to actual home directory
    task = task.replace('~', os.path.expanduser('~'))

    with open('prompts/system.txt', 'r') as f:
        system = f.read()
    with open('prompts/planner.txt', 'r') as f:
        planner = f.read()

    tools_desc = '\n'.join([
        f"- {name}: {tool.input_spec} -> {tool.output_spec}"
        for name, tool in REGISTRY.items()
    ])

    memory_desc = '\n'.join([str(m) for m in memory]) if memory else "No memory entries"

    return f"{system}\n\n{planner}\n\nAvailable tools:\n{tools_desc}\n\nMemory:\n{memory_desc}\n\nTask: {task}\n\nProvide plan in JSON format."

def parse_plan(response_text: str):
    try:
        # Try to find JSON in markdown code blocks first
        if '```json' in response_text:
            start = response_text.find('```json') + 7
            end = response_text.find('```', start)
            json_text = response_text[start:end].strip()
        elif '```' in response_text:
            start = response_text.find('```') + 3
            end = response_text.find('```', start)
            json_text = response_text[start:end].strip()
        else:
            start = response_text.find('{')
            end = response_text.rfind('}') + 1
            if start == -1 or end == 0:
                return Err("ParseError", "No JSON found in response")
            json_text = response_text[start:end]

        data = json.loads(json_text)

        if 'goal' not in data or 'steps' not in data:
            return Err("ParseError", "Missing goal or steps")

        if len(data['steps']) > 32:
            return Err("ValidationError", "Plan exceeds 32 steps")

        steps = []
        for step_data in data['steps']:
            step_type = step_data.get('type', '').lower()

            if step_type == 'halt':
                steps.append(Halt(reason=step_data.get('reason', 'Complete')))
            elif step_type in ('tool', 'toolcall'):
                name = step_data.get('name')
                if name not in REGISTRY:
                    return Err("ValidationError", f"Unknown tool: {name}")
                steps.append(ToolCall(name=name, args=step_data.get('args', {})))
            else:
                return Err("ParseError", f"Invalid step type: {step_type}")

        return Ok({'plan': Plan(goal=data['goal'], steps=tuple(steps))})

    except json.JSONDecodeError as e:
        return Err("ParseError", f"Invalid JSON: {str(e)}")
    except Exception as e:
        return Err("ParseError", str(e))

def generate_plan(state: State) -> State:
    prompt = render_prompt(state.input, state.memory)
    response = gemini_complete(prompt)

    result = parse_plan(response['text'])

    if isinstance(result, Ok):
        return replace(
            state,
            plan=result.value['plan'],
            history=state.history + (PlanGeneration(response['tokens'], time()),),
            token_count=state.token_count + response['tokens']
        )
    else:
        return replace(
            state,
            status="ERROR",
            history=state.history + (ErrorEvent(result.error_type, result.message, time()),)
        )
