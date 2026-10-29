"""ASON plan validator — enforces policy against APEX contract."""
from __future__ import annotations
from .schema import ASONRequest, ASONResult

_BLOCKED_TOOLS = {"shell"}  # tools never permitted regardless of policy

_BLAST_RADIUS_BLOCKS: dict[str, set[str]] = {
    "none":    {"write_file", "delete_file", "memory_write", "http_get", "http_post", "rag_multi_query"},
    "local":   {"http_get", "http_post", "rag_multi_query"},
    "network": set(),
}

_CLASSIFIED_TOOLS = {"read_file", "memory_read"} | _BLAST_RADIUS_BLOCKS["none"]


def validate(req: ASONRequest) -> ASONResult:
    violations: list[str] = []

    if len(req.plan.steps) > req.policy.max_steps:
        violations.append(
            f"plan has {len(req.plan.steps)} steps; policy max_steps={req.policy.max_steps}"
        )

    allowed = set(req.policy.allowed_tools)
    for i, step in enumerate(req.plan.steps):
        if step.tool in _BLOCKED_TOOLS:
            violations.append(f"step {i}: tool '{step.tool}' is unconditionally blocked")
        elif step.tool not in _CLASSIFIED_TOOLS:
            violations.append(f"step {i}: tool '{step.tool}' has no blast-radius classification")
        elif allowed and step.tool not in allowed:
            violations.append(f"step {i}: tool '{step.tool}' not in allowed_tools")

    radius_blocks = _BLAST_RADIUS_BLOCKS.get(req.policy.blast_radius, set())
    for j, step in enumerate(req.plan.steps):
        if step.tool in radius_blocks:
            violations.append(
                f"step {j}: tool '{step.tool}' blocked by blast_radius='{req.policy.blast_radius}'"
            )

    if violations:
        return ASONResult(accepted=False, violations=violations, risk_level="high", summary="policy violations detected")

    return ASONResult(accepted=True, risk_level="none", summary="plan accepted")
