# APEX Test Results

**axiom-apex v2.0** · Pure-functional CLI framework · Gemini 2.5 Flash · MIT  
**Platform:** Linux · Python 3.14.3 · pytest 8.4.2  
**Full suite:** `pytest apex/tests/test_apex.py -v --timeout=120`  
**Result: 65 passed, 2 xfailed in 84.05s (0:01:24)**

---

## Summary

| Category | Tests | Passed | XFailed |
|---|---|---|---|
| Config | 7 | 5 | 2 |
| CLI Flags | 7 | 7 | — |
| Plan Schema | 10 | 10 | — |
| State Immutability | 8 | 8 | — |
| Tool Registry | 14 | 14 | — |
| Memory (SQLite) | 8 | 8 | — |
| Integration (E2E) | 13 | 13 | — |
| **Total** | **67** | **65** | **2** |

---

## Unit Tests
`pytest apex/tests/test_apex.py -m "not integration" -v`  
**Result: 52 passed, 2 xfailed in 34.65s**

### Config (`TestConfig`)
Validates environment resolution, frozen dataclass contract, and custom DB path handling.

| Test | Result |
|---|---|
| `test_missing_api_key_exits_nonzero` | XFAIL — see known bug below |
| `test_missing_api_key_error_message` | XFAIL — see known bug below |
| `test_load_config_raises_on_missing_key` | PASS |
| `test_load_config_returns_frozen_dataclass` | PASS |
| `test_custom_db_path_respected` | PASS |
| `test_custom_db_path_creates_file` | PASS |
| `test_load_config_db_path_is_path_object` | PASS |

### CLI Flags (`TestFlags`)
Validates `--dry-run`, `--trace`, and `--version` behaviour.

| Test | Result | Notes |
|---|---|---|
| `test_version_flag` | PASS | |
| `test_dry_run_produces_json` | PASS | Status block appended after JSON on stdout; extracted via `raw_decode()` |
| `test_dry_run_no_side_effects` | PASS | |
| `test_dry_run_steps_have_type_field` | PASS | |
| `test_dry_run_last_step_is_halt` | PASS | |
| `test_trace_writes_to_stderr` | PASS | `--dry-run` suppresses tool events; test uses real execution |
| `test_trace_execution_emits_tool_events` | PASS | |

### Plan Schema (`TestPlanSchema`)
Validates `parse_plan()` — the schema enforcement boundary between LLM output and tool execution.

| Test | Result | Notes |
|---|---|---|
| `test_valid_plan_returns_plan_instance` | PASS | |
| `test_valid_plan_goal_preserved` | PASS | |
| `test_plan_missing_goal_returns_err` | PASS | |
| `test_plan_missing_steps_returns_err` | PASS | |
| `test_plan_unknown_step_type_returns_err` | PASS | |
| `test_plan_tool_step_missing_name_returns_err` | PASS | |
| `test_plan_unknown_tool_name_returns_err` | PASS | Validated against registry |
| `test_plan_exceeding_32_steps_returns_err` | PASS | 32-step limit enforced |
| `test_plan_invalid_json_returns_err` | PASS | Returns `Err`, never raises |
| `test_toolcall_step_type_accepted` | PASS | Both `tool` and `toolcall` accepted |

### State Immutability (`TestState`)
Validates the pure-functional design axiom: `State` is a frozen dataclass updated only via `dataclasses.replace()`.

| Test | Result |
|---|---|
| `test_state_is_frozen` | PASS |
| `test_replace_produces_new_instance` | PASS |
| `test_initial_state_status_is_running` | PASS |
| `test_initial_state_has_empty_history` | PASS |
| `test_initial_state_has_no_plan` | PASS |
| `test_initial_state_zero_token_count` | PASS |
| `test_original_unchanged_after_replace` | PASS |
| `test_input_preserved` | PASS |

### Tool Registry (`TestToolRegistry`)
Validates all four documented tools exist and that core effects behave correctly in isolation.

| Test | Result | Notes |
|---|---|---|
| `test_shell_tool_exists` | PASS | |
| `test_read_file_tool_exists` | PASS | |
| `test_write_file_tool_exists` | PASS | |
| `test_http_get_tool_exists` | PASS | |
| `test_shell_effect_runs_command` | PASS | |
| `test_shell_effect_returns_code_key` | PASS | Key is `code`, not `exit_code` or `returncode` |
| `test_shell_effect_zero_on_success` | PASS | |
| `test_shell_effect_nonzero_on_failure` | PASS | |
| `test_shell_pipe_composition` | PASS | |
| `test_shell_and_operator` | PASS | |
| `test_write_read_roundtrip` | PASS | |
| `test_write_file_creates_parents` | PASS | |
| `test_http_get_effect_returns_status` | PASS | |
| `test_http_get_effect_returns_body` | PASS | |

### Memory — SQLite (`TestMemory`)
Validates the persistent key-value store. All tests use isolated `tmp_path` databases.

| Test | Result | Notes |
|---|---|---|
| `test_write_and_read` | PASS | |
| `test_read_missing_key_returns_none` | PASS | Returns `{"value": None}` |
| `test_overwrite_value` | PASS | Latest write wins |
| `test_list_all_entries` | PASS | No-key read returns all entries |
| `test_json_serialisable_values` | PASS | Nested dict round-trips cleanly |
| `test_write_returns_written_true` | PASS | `{"written": True}` confirmed |
| `test_concurrent_writes_isolated` | PASS | 5 threads, no corruption |
| `test_memory_persists_across_instances` | PASS | Fresh instance reads prior data |

---

## Integration Tests (E2E)
`pytest apex/tests/test_apex.py -v --timeout=120`  
**Result: 13/13 passed**

Live subprocess invocations against the Gemini 2.5 Flash API.

| Test | Result | Notes |
|---|---|---|
| `test_write_file_task` | PASS | File created with correct content |
| `test_read_file_task` | PASS | |
| `test_shell_task` | PASS | Date written via shell tool |
| `test_memory_roundtrip` | PASS | Value persisted across two invocations |
| `test_http_get_task` | PASS | Live URL fetched and saved |
| `test_multistep_create_and_verify` | PASS | Both files created in single plan |
| `test_dry_run_zero_exit` | PASS | |
| `test_dry_run_valid_json_output` | PASS | |
| `test_error_handling_bad_path` | PASS | No unhandled exception on bad path |
| `test_parallel_independent_tasks` | PASS | Two concurrent processes, no state corruption |
| `test_exit_code_zero_on_success` | PASS | |
| `test_exit_code_not_unexpected_state` | PASS | Exit code 2 never occurs |
| `test_output_nonempty_on_success` | PASS | |

---

## Known Bug: ADC Credential Bypass (XFAIL)

**Affected tests:** `test_missing_api_key_exits_nonzero`, `test_missing_api_key_error_message`

**README states:** *"APEX exits immediately without GEMINI_API_KEY."*

**Actual behaviour:** `load_config()` correctly raises `ValueError` when
`GEMINI_API_KEY` is absent — confirmed by `test_load_config_raises_on_missing_key`.
However, `genai.Client(api_key="")` silently falls back to Application Default
Credentials via `~/.config/gcloud/`, authenticating successfully and bypassing
the process exit on any machine with Google Cloud credentials configured.

**Proposed fix in `apex/llm.py`:**
```python
# Before
client = genai.Client(api_key=api_key)

# After — None disables ADC fallback
client = genai.Client(api_key=api_key or None)
```

These tests are marked `xfail(strict=True)`. If the bug is fixed they will
surface as `XPASS` and prompt removal of the mark.

---

## Bugs and Findings

| # | Severity | Location | Description | Status |
|---|---|---|---|---|
| 1 | Medium | `apex/llm.py` | `genai.Client` falls back to ADC when `api_key` is empty, violating README guarantee | Open |
| 2 | Low | `apex/memory.py` | `make_memory_tools` requires `Path`, not `str` — passing `str` raises `AttributeError: 'str' object has no attribute 'parent'` | Found by testing |
| 3 | Low | `apex/__main__.py` | `--dry-run` appends status text after plan JSON on stdout, making output unparseable by `json.loads()` | Found by testing |
