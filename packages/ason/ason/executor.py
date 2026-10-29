"""ASON executor — binds policy authorization to exact APEX execution."""
from __future__ import annotations

import hashlib
import json
import urllib.error
import urllib.request
from uuid import uuid4

from .schema import ASONRequest, ASONResult
from .validator import validate


class ASONExecutor:
    def __init__(
        self,
        apex_url: str = "http://127.0.0.1:8080",
        api_key: str | None = None,
        authority_ref: str | None = None,
    ):
        self.apex_url = apex_url.rstrip("/")
        self.api_key = api_key
        self.authority_ref = authority_ref

    def _headers(self) -> dict:
        h = {"Content-Type": "application/json"}
        if self.api_key:
            h["X-Apex-Key"] = self.api_key
        return h

    def submit(self, req: ASONRequest, *, authority_ref: str | None = None) -> dict:
        result: ASONResult = validate(req)
        if not result.accepted:
            return {"accepted": False, "violations": result.violations, "apex_response": None}

        authority = authority_ref if authority_ref is not None else self.authority_ref
        if not isinstance(authority, str) or not authority.strip():
            return {
                "accepted": True,
                "violations": [],
                "apex_response": None,
                "error": "authority_ref is required for authorized APEX dispatch",
            }

        plan = _apex_plan(req)
        try:
            authorization = _authorization(req, plan, authority.strip())
            payload = json.dumps(
                {"plan": plan, "authorization": authorization},
                ensure_ascii=False,
                separators=(",", ":"),
                allow_nan=False,
            ).encode()
        except (TypeError, ValueError) as exc:
            return {
                "accepted": True,
                "violations": [],
                "apex_response": None,
                "error": f"authorization payload is not canonical JSON: {exc}",
            }

        http_req = urllib.request.Request(
            f"{self.apex_url}/authorized-run",
            data=payload,
            headers=self._headers(),
            method="POST",
        )
        try:
            with urllib.request.urlopen(http_req, timeout=310) as resp:
                apex_response = json.loads(resp.read())
        except urllib.error.HTTPError as exc:
            return {
                "accepted": True,
                "violations": [],
                "authorization": authorization,
                "apex_response": None,
                "error": str(exc),
            }
        except Exception as exc:
            return {
                "accepted": True,
                "violations": [],
                "authorization": authorization,
                "apex_response": None,
                "error": str(exc),
            }

        return {
            "accepted": True,
            "violations": [],
            "authorization": authorization,
            "apex_response": apex_response,
        }


def _canonical_digest(value: dict) -> str:
    encoded = json.dumps(
        value,
        sort_keys=True,
        ensure_ascii=False,
        separators=(",", ":"),
        allow_nan=False,
    )
    return hashlib.sha256(encoded.encode("utf-8")).hexdigest()


def _authorization(req: ASONRequest, plan: dict, authority_ref: str) -> dict:
    """Create the exact policy/plan binding that APEX must durably persist."""
    return {
        "authorization_id": str(uuid4()),
        "approved_plan_digest": _canonical_digest(plan),
        "policy_digest_or_ref": _canonical_digest(req.policy.model_dump(mode="json")),
        "authority_ref": authority_ref,
        "decision": True,
    }


def _apex_plan(req: ASONRequest) -> dict:
    """Translate the approved steps to APEX's exact-execution representation."""
    return {
        "goal": "Execute ASON-approved plan",
        "steps": [
            {"type": "tool", "name": step.tool, "args": step.args}
            for step in req.plan.steps
        ] + [{"type": "halt", "reason": "ASON-approved plan complete"}],
    }
