"""Paranoid plan validator — audits generated plans for dangerous operations before execution."""
from __future__ import annotations
import json
import re
from apex.core.types import Plan, Halt, ToolCall

# ---------------------------------------------------------------------------
# Static deterministic prefilter (runs BEFORE LLM audit)
# ---------------------------------------------------------------------------

_BLOCK_PATTERNS = [
    re.compile(r"rm\s+-[rf]+\s+/"),
    re.compile(r"chmod\s+777\s+/"),
    re.compile(r"curl\s+.*\|\s*sh"),
    re.compile(r"wget\s+.*\|\s*sh"),
    re.compile(r"dd\s+if=/dev/zero"),
    re.compile(r"mkfs\."),
    re.compile(r">\s*/dev/sd"),
    re.compile(r":\(\)\{:\|:&\};"),
]


def _static_check(plan: Plan) -> list[dict]:
    import os
    home = str(os.path.expanduser("~"))
    violations = []
    for i, step in enumerate(plan.steps):
        if not isinstance(step, ToolCall):
            continue
        args_str = json.dumps(step.args)
        for pat in _BLOCK_PATTERNS:
            if pat.search(args_str):
                violations.append({"step": i, "tool": step.name,
                                   "reason": "blocked pattern: " + pat.pattern})
        if step.name == "write_file":
            path_arg = step.args.get("path", "")
            if path_arg and not str(path_arg).startswith(home):
                violations.append({"step": i, "tool": step.name,
                                   "reason": "write outside HOME: " + str(path_arg)})
    return violations


def static_audit(plan: Plan) -> dict:
    violations = _static_check(plan)
    if violations:
        return {"safe": False, "risk_level": "critical",
                "findings": violations,
                "summary": "Static prefilter blocked " + str(len(violations)) + " pattern(s)"}
    return {"safe": True, "risk_level": "none", "findings": [], "summary": "Static check passed"}

_PARANOID_PROMPT = """You are a security auditor for an AI agent execution system.

You will be given an execution plan as JSON. Audit every tool call for:
- Destructive filesystem operations (rm -rf, shred, truncate, overwrite of system files)
- Exfiltration patterns (curl/wget posting data to external URLs, writing credentials to files)
- Privilege escalation (sudo, su, chmod 777 on system paths, /etc writes)
- Self-modification of agent source code outside an explicit RSI context
- Irreversible operations on paths outside /tmp, ~/tmp, or explicitly user-specified output paths
- Infinite loops or resource exhaustion patterns

Respond ONLY with a JSON object:
{
  "safe": true | false,
  "risk_level": "none" | "low" | "medium" | "high" | "critical",
  "findings": [
    {"step": <step_index>, "tool": "<tool_name>", "reason": "<why dangerous>"}
  ],
  "summary": "<one sentence>"
}

If safe=true, findings must be empty.
Do not include any text outside the JSON object.

Plan to audit:
"""


def audit_plan(plan: Plan, *, api_key: str, provider: str = "gemini") -> dict:
    """
    Run the paranoid audit on a Plan. Returns parsed audit result dict.
    Raises ValueError if LLM response is unparseable.
    """
    steps = []
    for i, step in enumerate(plan.steps):
        if isinstance(step, ToolCall):
            steps.append({"index": i, "type": "tool", "name": step.name, "args": step.args})
        elif isinstance(step, Halt):
            steps.append({"index": i, "type": "halt", "reason": step.reason})

    plan_json = json.dumps({"goal": plan.goal, "steps": steps}, indent=2)
    prompt = _PARANOID_PROMPT + plan_json

    static = static_audit(plan)
    if not static["safe"]:
        return static
    from apex.llm import gemini_complete
    result = gemini_complete(prompt, api_key=api_key)
    text = result["text"].strip()

    # Strip markdown fences if present
    if text.startswith("```"):
        lines = text.splitlines()
        text = "\n".join(lines[1:-1] if lines[-1].strip() == "```" else lines[1:])

    try:
        return json.loads(text)
    except json.JSONDecodeError as e:
        raise ValueError(f"Paranoid auditor returned unparseable response: {e}\n{text}")


def format_audit_report(audit: dict) -> str:
    lines = [f"[paranoid] risk={audit.get('risk_level', '?')} safe={audit.get('safe')}"]
    lines.append(f"[paranoid] {audit.get('summary', '')}")
    for f in audit.get("findings", []):
        lines.append(f"[paranoid] step {f['step']} ({f['tool']}): {f['reason']}")
    return "\n".join(lines)
