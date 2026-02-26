# bin/

CLI entry point for APEX.

## apex

```bash
apex "<task>"
```

Requires `GEMINI_API_KEY` in environment. Must be run from the repo root — the planner resolves `prompts/system.txt` relative to the working directory.

```bash
cd ~/apex
export GEMINI_API_KEY=your-key
export PATH="$PATH:$(pwd)/bin"

apex "write system info to ~/report.txt"
```

Exits `0` on `HALTED` status, `1` otherwise — composable in bash pipelines and scripts.
