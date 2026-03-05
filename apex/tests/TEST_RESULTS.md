# APEX Test Results

**apex-cli v2.0** · Pure-functional CLI framework · Gemini 2.5 Flash · MIT  
Tested: `YYYY-MM-DD` · Python `3.x.x` · Platform: `linux/darwin`

---

## Running the Suite
```bash
# Unit tests only (no API key required)
pytest tests/test_apex.py -m "not integration" -v

# Full suite (requires GEMINI_API_KEY)
export GEMINI_API_KEY=your-key
pytest tests/test_apex.py -v

# With coverage report
pytest tests/test_apex.py -m "not integration" --cov=apex --cov-report=term-missing
```

---

## Results Summary

| Category | Tests | Passed | Skipped | Failed |
|---|---|---|---|---|
| Config | 4 | | | |
| CLI Flags | 7 | | | |
| Plan Schema Validation | 6 | | | |
| State Immutability | 4 | | | |
| Tool Registry | 12 | | | |
| Memory (SQLite) | 7 | | | |
| Integration (E2E) | 13 | | | |
| **Total** | **53** | | | |

---

## Coverage by Feature

### Config (`TestConfig`)
Validates that missing or misconfigured environment variables are caught at startup before any LLM call is made.

| Test | What It Verifies |
|---|---|
| `test_missing_api_key_exits_nonzero` | Process exits with non-zero code when `GEMINI_API_KEY` is absent |
| `test_missing_api_key_error_message` | Error output names the missing variable explicitly |
| `test_custom_db_path_respected` | `APEX_DB_PATH` env var is accepted without config errors |
| `test_custom_db_path_creates_file` | Memory writes actually land at the custom path, not `~/.apex/memory.db` |

---

### CLI Flags (`TestFlags`)
Validates the documented CLI surface: `--dry-run`, `--trace`, `--version`.

| Test | What It Verifies |
|---|---|
| `test_version_flag` | `--version` exits 0 and prints a non-empty string |
| `test_dry_run_produces_json` | `--dry-run` output is parseable JSON with `goal` and `steps` |
| `test_dry_run_no_side_effects` | `--dry-run` never creates files on disk |
| `test_dry_run_steps_have_type_field` | Every step in a dry-run plan has a `type` field |
| `test_dry_run_last_step_is_halt` | All plans terminate with a `halt` step |
| `test_trace_writes_to_stderr` | `--trace` emits output to stderr |
| `test_trace_execution_emits_tool_events` | `--trace` during real execution emits `[tool]` or `[plan]` events |

---

### Plan Schema Validation (`TestPlanSchema`)
Validates the schema-enforcement boundary: APEX must reject malformed LLM output before any tool is invoked.

| Test | What It Verifies |
|---|---|
| `test_valid_plan_passes_validation` | Well-formed plans are accepted |
| `test_plan_missing_goal_rejected` | Plans without `goal` are rejected |
| `test_plan_missing_steps_rejected` | Plans without `steps` are rejected |
| `test_plan_unknown_step_type_rejected` | Unknown step types are rejected |
| `test_plan_tool_step_missing_name_rejected` | Tool steps without `name` are rejected |
| `test_empty_steps_rejected` | Plans with zero steps are rejected |

---

### State Immutability (`TestState`)
Validates the pure-functional design axiom: `State` is a frozen dataclass; updates produce new instances.

| Test | What It Verifies |
|---|---|
| `test_state_is_frozen` | Direct attribute mutation raises `AttributeError` or `TypeError` |
| `test_replace_produces_new_instance` | `dataclasses.replace()` returns a distinct object |
| `test_initial_state_status` | Fresh state has a recognised status value |
| `test_original_unchanged_after_replace` | Replacing a field does not mutate the source object |

---

### Tool Registry (`TestToolRegistry`)
Validates that all six documented tools exist and that core tool effects behave correctly in isolation.

| Test | What It Verifies |
|---|---|
| `test_shell_tool_exists` | `SHELL` tool is registered |
| `test_read_file_tool_exists` | `READ_FILE` tool is registered |
| `test_write_file_tool_exists` | `WRITE_FILE` tool is registered |
| `test_http_get_tool_exists` | `HTTP_GET` tool is registered |
| `test_shell_effect_runs_command` | Shell effect executes commands and returns stdout |
| `test_shell_effect_returns_exit_code` | Shell effect includes an exit code field |
| `test_shell_effect_nonzero_on_failure` | Failing commands produce a non-zero exit code |
| `test_shell_pipe_composition` | Pipe operator (`\|`) works — documented concurrency primitive |
| `test_shell_and_operator` | `&&` chaining works as documented |
| `test_write_read_roundtrip` | Write then read returns the original content |
| `test_write_file_creates_parents` | Writing to a nested path creates all intermediate directories |
| `test_http_get_effect_returns_status` | HTTP GET returns a status code field |
| `test_http_get_effect_returns_body` | HTTP GET returns a non-empty response body |

---

### Memory — SQLite (`TestMemory`)
Validates the persistent key-value store backed by `~/.apex/memory.db` (or `APEX_DB_PATH`).

| Test | What It Verifies |
|---|---|
| `test_write_and_read` | Written values are immediately readable |
| `test_read_missing_key` | Missing keys return `None` or an error structure — never raise |
| `test_overwrite_value` | Writing the same key twice keeps only the latest value |
| `test_list_all_entries` | `memory_read` with no key lists all stored entries |
| `test_json_serialisable_values` | Nested dicts and lists round-trip without data loss |
| `test_concurrent_writes_isolated` | 5 concurrent threads writing to the same DB produce no corruption |
| `test_memory_persists_across_instances` | A fresh `make_memory_tools` instance can read data from a prior one |

---

### Integration — End-to-End (`TestIntegration`)
Full subprocess invocations against the live Gemini API. All tests require `GEMINI_API_KEY`.

| Test | What It Verifies |
|---|---|
| `test_write_file_task` | NL task produces correct file with correct content |
| `test_read_file_task` | APEX reads an existing file without error |
| `test_shell_task` | APEX uses the shell tool to write dynamic output |
| `test_memory_roundtrip` | Memory write in one invocation is readable in the next |
| `test_http_get_task` | APEX fetches a live URL and saves it to disk |
| `test_multistep_create_and_verify` | A two-file task runs both steps and produces both files |
| `test_dry_run_zero_exit` | `--dry-run` exits 0 via the live planner |
| `test_dry_run_valid_json_output` | Live planner output is valid JSON with non-empty steps |
| `test_error_handling_bad_path` | Unreadable path doesn't crash with an unhandled exception |
| `test_parallel_independent_tasks` | Two concurrent APEX processes produce independent, uncorrupted output |
| `test_exit_code_zero_on_success` | Successful `HALTED` plans exit with code `0` |
| `test_exit_code_not_unexpected_state` | Exit code `2` (unexpected terminal state) never occurs |
| `test_output_nonempty_on_success` | Successful invocations produce some output or file evidence |

---

## Architecture Properties Exercised

| Design Axiom | Test(s) |
|---|---|
| Immutability — frozen dataclasses | `TestState` (all 4) |
| Schema-validated plans | `TestPlanSchema` (all 6) |
| Zero implicit configuration | `TestConfig` (all 4) |
| Memory tools are closures | `test_memory_persists_across_instances` |
| Bash is the concurrency primitive | `test_parallel_independent_tasks`, `test_shell_pipe_composition`, `test_shell_and_operator` |
| Exit codes 0 / 1 / not-2 | `test_exit_code_zero_on_success`, `test_exit_code_not_unexpected_state` |

---

## Known Untested Scenarios

These are documented constraints or features not covered by automated tests, with rationale:

| Scenario | Reason Not Tested |
|---|---|
| `--interactive` mode | Requires stdin automation; impractical as a subprocess test |
| 32-step plan limit enforcement | Difficult to reliably generate a 32-step plan via NL prompt |
| 300-second tool timeout (SIGALRM) | Requires a deliberately hung process; flaky in CI |
| 10 MB tool output cap | Generating 10 MB of shell output is slow and brittle |
| JS-rendered pages via `http_get` | Documented as unsupported — negative test would be environment-dependent |

---

*Generated against apex-cli v2.0. Update the summary table above after each test run.*
