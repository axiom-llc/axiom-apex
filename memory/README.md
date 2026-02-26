# memory/

SQLite-backed persistent key-value store for cross-session agent state.

## sqlite.py

Read and write named values across apex sessions. Accessed via `memory_read` and `memory_write` tools.

```bash
apex "save current project name to memory as active_project"
apex "read active_project from memory"
```

Database file: `memory/apex_memory.db` (auto-created on first write, gitignored).

Useful for multi-step workflows where state needs to persist between separate apex calls or script runs.
