# prompts/

System prompts for the planner and execution loop.

## system.txt
Core agent instructions. Defines tool usage rules, output format requirements, and behavioral constraints. Resolved relative to the working directory — always run apex from repo root.

## planner.txt
Planning-specific guidance. Shapes how the LLM decomposes tasks into structured execution steps.

Editing these files directly changes agent behavior without any code changes. Keep modifications minimal and test against known-good tasks after any edit.
