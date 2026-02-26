"""Main execution loop"""
import signal
from contextlib import contextmanager
from dataclasses import replace
from time import time
from core.state import State, create_initial_state
from core.planner import generate_plan
from core.types import Halt, ToolCall, ToolExecution, Ok, Err
from tools.registry import REGISTRY

class ApexTimeoutError(Exception):
    pass

@contextmanager
def timeout(seconds: int):
    def handler(signum, frame):
        raise ApexTimeoutError()
    
    old_handler = signal.signal(signal.SIGALRM, handler)
    signal.alarm(seconds)
    try:
        yield
    finally:
        signal.alarm(0)
        signal.signal(signal.SIGALRM, old_handler)

def run(input_str: str) -> State:
    state = create_initial_state(input_str)
    state = generate_plan(state)
    
    if state.status != "RUNNING":
        return state
    
    while state.status == "RUNNING" and state.plan and state.plan.steps:
        step = state.plan.steps[0]
        
        if isinstance(step, Halt):
            return replace(state, status="HALTED")
        
        if isinstance(step, ToolCall):
            tool = REGISTRY[step.name]
            
            try:
                with timeout(300):
                    output = tool.effect(step.args)
                    if len(str(output)) > 10_485_760:
                        result = Err("ToolExecutionError", "Output exceeds 10MB")
                    else:
                        result = Ok(output) if isinstance(output, dict) else Ok({'output': output})
            except ApexTimeoutError:
                result = Err("ToolTimeout", f"{step.name} exceeded 300s")
            except Exception as e:
                result = Err("ToolExecutionError", str(e))
            
            state = replace(
                state,
                plan=replace(state.plan, steps=state.plan.steps[1:]),
                history=state.history + (ToolExecution(step.name, step.args, result, time()),)
            )
            
            if isinstance(result, Err):
                return replace(state, status="ERROR")
    
    return replace(state, status="HALTED")
