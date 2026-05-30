"""ASON core schema — APEX contract types."""
from __future__ import annotations
from typing import Literal
from pydantic import BaseModel, Field


class Policy(BaseModel):
    max_steps: int = Field(default=16, ge=1, le=32)
    allowed_tools: list[str] = Field(default_factory=list)
    blast_radius: Literal["none", "local", "network"] = "local"
    rollback_on_failure: bool = True


class ApexPlanStep(BaseModel):
    tool: str
    args: dict


class ApexPlan(BaseModel):
    steps: list[ApexPlanStep]


class ASONRequest(BaseModel):
    plan: ApexPlan
    policy: Policy = Field(default_factory=Policy)


class ASONResult(BaseModel):
    accepted: bool
    violations: list[str] = Field(default_factory=list)
    risk_level: Literal["none", "low", "medium", "high"] = "none"
    summary: str = ""
