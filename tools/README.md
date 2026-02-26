# tools/

Effect implementations. All I/O happens here — core/ stays pure.

## basic.py

| Tool | Description |
|---|---|
| `shell` | Execute arbitrary shell commands via subprocess |
| `read_file` | Read file contents from disk |
| `write_file` | Write content to file (creates path if needed) |
| `http_get` | HTTP GET via curl |
| `memory_read` | Read named value from SQLite store |
| `memory_write` | Write named value to SQLite store |

## registry.py

Tool registration and dispatch. Maps tool names (as returned by the planner) to their implementations in `basic.py`. To add a tool: implement it in `basic.py`, register it here.

## Adding a Tool

1. Implement the function in `basic.py` with signature `(params: dict) -> ToolResult`
2. Register in `registry.py`: `register("tool_name", your_function)`
3. Document the tool's name and expected params in `prompts/system.txt` so the planner knows to use it
