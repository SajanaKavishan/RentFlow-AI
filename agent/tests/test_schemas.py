from __future__ import annotations

import pytest
from pydantic import ValidationError

from app.schemas.analysis import (
    ApplicationDataAnalysis,
    ConsistencyAnalysis,
    DocumentAnalysis,
    FinalAgentSummary,
)
from app.schemas.plan import ALLOWED_PLAN_STEPS, Plan
from app.schemas.requests import ApplicationValidationRequest


def _summary(**overrides):
    values = {
        "recommendation": "Manual review required",
        "summary": "A landlord must review the structured findings.",
        "key_findings": [],
        "warnings": [],
        "requires_human_approval": True,
        "agent_version": "test",
    }
    values.update(overrides)
    return values


def test_fixed_allow_listed_plan_is_valid() -> None:
    plan = Plan(steps=list(ALLOWED_PLAN_STEPS))

    assert tuple(plan.steps) == ALLOWED_PLAN_STEPS


def test_planner_rejects_unknown_step_name() -> None:
    with pytest.raises(ValidationError):
        Plan.model_validate(
            {
                "steps": [
                    "analyze_application_data",
                    "query_database",
                    "analyze_consistency",
                    "summarize_findings",
                ]
            }
        )


def test_planner_rejects_reordered_steps() -> None:
    with pytest.raises(ValidationError):
        Plan(steps=list(reversed(ALLOWED_PLAN_STEPS)))


def test_final_summary_always_requires_human_approval() -> None:
    with pytest.raises(ValidationError):
        FinalAgentSummary.model_validate(_summary(requires_human_approval=False))


@pytest.mark.parametrize("recommendation", ["Approve tenant", "Reject tenant", "Good tenant", "Bad tenant"])
def test_prohibited_recommendation_values_are_rejected(recommendation: str) -> None:
    with pytest.raises(ValidationError):
        FinalAgentSummary.model_validate(_summary(recommendation=recommendation))


def test_protected_characteristic_and_risk_fields_are_absent_from_schemas() -> None:
    schema_models = [
        ApplicationValidationRequest,
        ApplicationDataAnalysis,
        DocumentAnalysis,
        ConsistencyAnalysis,
        FinalAgentSummary,
    ]
    prohibited = {
        "race", "religion", "gender", "age", "risk_score", "risk_rating",
        "fraud_score", "tenant_score", "trust_score",
    }

    for schema_model in schema_models:
        assert prohibited.isdisjoint(schema_model.model_fields)
