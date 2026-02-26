# core/

Pure-functional execution engine. No I/O, no side effects — all effects are delegated to `tools/`.

## Modules

### loop.py
Main execution loop. Accepts a task string, drives plan generation and tool execution, returns final state. Entry point for `bin/apex`.

### planner.py
LLM interface for plan generation. Takes current state, returns a structured execution plan (JSON). Calls `llm/` — no direct API calls here.

### state.py
Immutable state management via `dataclasses.replace()`. All state transitions produce new state objects. Provides `format_output()` for CLI rendering.

### types.py
Shared type definitions. `State`, `Plan`, `Step`, `ToolResult`, `Status`. Import from here — never define types inline.

## Design

The loop is the only stateful coordinator. Planner and state are pure functions. This separation makes the execution path fully inspectable and testable without mocking.
