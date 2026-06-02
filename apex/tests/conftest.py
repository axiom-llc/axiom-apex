from __future__ import annotations
import sys
from pathlib import Path
voice_agent_dir = str(Path(__file__).parent.parent / "examples" / "voice-agent")
if voice_agent_dir not in sys.path:
    sys.path.insert(0, voice_agent_dir)

import sys
import types
import json
import urllib.request
import urllib.error

# 1. Force import of apex.core.rag to register the "rag" module mapping
import apex.core.rag

# 2. Register "ason" package compatibility mapping
from apex.core import schema, validator, rollback
from apex.core.schema import ASONRequest, ASONResult, ApexPlan, ApexPlanStep, Policy
from apex.core.validator import validate
from apex.core.rollback import generate_rollback

ason_mod = types.ModuleType("ason")
sys.modules["ason"] = ason_mod
sys.modules["ason.schema"] = schema
sys.modules["ason.validator"] = validator
sys.modules["ason.rollback"] = rollback

def _plan_to_task(req: ASONRequest) -> str:
    data = {
        "ason_plan": [{"tool": s.tool, "args": s.args} for s in req.plan.steps],
        "ason_policy": {
            "max_steps": req.policy.max_steps,
            "allowed_tools": req.policy.allowed_tools,
            "blast_radius": req.policy.blast_radius,
            "rollback_on_failure": req.policy.rollback_on_failure,
        }
    }
    return json.dumps(data)

class ASONExecutor:
    def __init__(self, api_key: str = "", base_url: str = "http://127.0.0.1:8080"):
        self.api_key = api_key
        self.base_url = base_url

    def submit(self, req: ASONRequest) -> dict:
        val_res = validate(req)
        if not val_res.accepted:
            return {
                "accepted": False,
                "violations": val_res.violations,
                "risk_level": val_res.risk_level,
                "summary": val_res.summary,
            }

        task_str = _plan_to_task(req)

        try:
            url = f"{self.base_url}/run"
            data_bytes = json.dumps({"task": task_str}).encode("utf-8")
            headers = {
                "Content-Type": "application/json",
            }
            if self.api_key:
                headers["X-Apex-Key"] = self.api_key

            url_req = urllib.request.Request(url, data=data_bytes, headers=headers, method="POST")
            with urllib.request.urlopen(url_req, timeout=300) as response:
                resp_data = json.loads(response.read().decode("utf-8"))
            
            return {
                "accepted": True,
                "error": None,
                "apex_response": resp_data,
            }
        except urllib.error.HTTPError as e:
            return {
                "accepted": True,
                "error": str(e),
                "apex_response": None,
            }
        except Exception as e:
            return {
                "accepted": True,
                "error": str(e),
                "apex_response": None,
            }

ason_executor = types.ModuleType("ason.executor")
ason_executor.ASONExecutor = ASONExecutor
ason_executor._plan_to_task = _plan_to_task
sys.modules["ason.executor"] = ason_executor
