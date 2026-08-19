"""Allow-listed planner output."""

from __future__ import annotations

from typing import Literal

from pydantic import Field, model_validator

from app.schemas.common import StrictModel


PlanStep = Literal[
    "analyze_application_data",
    "analyze_document_metadata",
    "verify_supporting_documents",
    "analyze_cross_document_consistency",
    "analyze_consistency",
    "summarize_findings",
]

ALLOWED_PLAN_STEPS: tuple[PlanStep, ...] = (
    "analyze_application_data",
    "analyze_document_metadata",
    "verify_supporting_documents",
    "analyze_cross_document_consistency",
    "analyze_consistency",
    "summarize_findings",
)


class Plan(StrictModel):
    steps: list[PlanStep] = Field(min_length=6, max_length=6)

    @model_validator(mode="after")
    def require_fixed_order(self) -> "Plan":
        if tuple(self.steps) != ALLOWED_PLAN_STEPS:
            raise ValueError("Plan must contain every allowed step exactly once in fixed order")
        return self
