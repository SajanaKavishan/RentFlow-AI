from __future__ import annotations

from typing import Any

import pytest
from fastapi.testclient import TestClient
from pydantic import ValidationError

from app.agents.maintenance_nodes import (
    MaintenanceAssessmentAgent,
    MaintenanceCoordinationAgent,
    UrgencyRiskAgent,
)
from app.schemas.maintenance import (
    MAINTENANCE_PLAN_STEPS,
    MaintenanceCoordinationRecommendation,
    MaintenanceCoordinationRequest,
    MaintenanceCoordinationSummary,
    MaintenanceInformationReview,
    MaintenanceIssueAssessment,
    MaintenancePlan,
    MaintenanceUrgencyAssessment,
)
from tests.conftest import FakeModelProvider, valid_maintenance_request


def valid_maintenance_responses() -> dict[str, Any]:
    return {
        "MaintenancePlan": {"steps": list(MAINTENANCE_PLAN_STEPS)},
        "MaintenanceIssueAssessment": {
            "recommended_category": "plumbing",
            "findings": ["Water leak reported in supplied description."],
            "explanation": "The request describes a plumbing issue.",
        },
        "MaintenanceUrgencyAssessment": {
            "recommended_priority": "high",
            "urgency_reason": "A continuing leak can cause property damage.",
            "warnings": [],
        },
        "MaintenanceInformationReview": {
            "available_information": ["title", "description", "category", "priority"],
            "missing_information": ["repair estimate"],
            "warnings": ["No estimate was supplied."],
        },
        "MaintenanceCoordinationRecommendation": {
            "recommended_category": "plumbing",
            "recommended_priority": "high",
            "next_action": "Schedule technician review",
            "reasoning": "A technician should review the leak promptly.",
            "warnings": ["No repair estimate was supplied."],
        },
        "MaintenanceCoordinationSummary": {
            "recommended_category": "plumbing",
            "recommended_priority": "high",
            "next_action": "Schedule technician review",
            "reasoning": "A technician should review the leak promptly.",
            "warnings": ["No repair estimate was supplied."],
            "agentVersion": "model-value-is-overridden",
        },
    }


class MaintenanceProvider(FakeModelProvider):
    def __init__(self, responses: dict[str, Any] | None = None) -> None:
        super().__init__(responses or valid_maintenance_responses())


class FailingMaintenanceProvider(MaintenanceProvider):
    async def generate_structured(self, **kwargs: Any) -> Any:
        del kwargs
        raise RuntimeError("maintenance-provider-secret")


def test_valid_request_returns_advisory_result_and_execution_metadata(
    settings, 
) -> None:
    provider = MaintenanceProvider()
    from app.main import create_app

    response = TestClient(create_app(settings=settings, model_provider=provider)).post(
        "/internal/maintenance-coordination/analyze",
        json=valid_maintenance_request(),
    )

    assert response.status_code == 200
    body = response.json()
    assert body["maintenanceRequestId"] == "maintenance-123"
    assert body["result"]["recommendedCategory"] == "plumbing"
    assert body["result"]["agentVersion"] == "test-1.0"
    assert body["executionMetadata"]["executedSteps"] == ["plan", *MAINTENANCE_PLAN_STEPS]


def test_maintenance_request_rejects_unknown_fields() -> None:
    payload = valid_maintenance_request()
    payload["unexpected"] = True

    with pytest.raises(ValidationError):
        MaintenanceCoordinationRequest.model_validate(payload)


def test_maintenance_plan_rejects_reordered_steps() -> None:
    with pytest.raises(ValidationError):
        MaintenancePlan(steps=list(reversed(MAINTENANCE_PLAN_STEPS)))


def test_graph_execution_order_is_fixed(settings) -> None:
    provider = MaintenanceProvider()
    from app.main import create_app

    response = TestClient(create_app(settings=settings, model_provider=provider)).post(
        "/internal/maintenance-coordination/analyze",
        json=valid_maintenance_request(),
    )

    assert response.status_code == 200
    assert provider.calls == [
        "MaintenancePlan",
        "MaintenanceIssueAssessment",
        "MaintenanceUrgencyAssessment",
        "MaintenanceInformationReview",
        "MaintenanceCoordinationRecommendation",
        "MaintenanceCoordinationSummary",
    ]


def test_maintenance_roles_execute_with_distinct_responsibilities_and_deterministic_order() -> None:
    assessment = MaintenanceAssessmentAgent(provider=None, timeout_seconds=1.0, agent_version="test")
    urgency = UrgencyRiskAgent(provider=None, timeout_seconds=1.0, agent_version="test")
    coordination = MaintenanceCoordinationAgent(provider=None, timeout_seconds=1.0, agent_version="test")

    assert assessment.role_name == "MaintenanceAssessmentAgent"
    assert urgency.role_name == "UrgencyRiskAgent"
    assert coordination.role_name == "MaintenanceCoordinationAgent"
    assert assessment.responsibility != urgency.responsibility
    assert urgency.responsibility != coordination.responsibility
    assert assessment.output_contract is MaintenanceIssueAssessment
    assert urgency.output_contract is MaintenanceUrgencyAssessment
    assert coordination.output_contract is MaintenanceCoordinationRecommendation

    state = {
        "maintenance_request": valid_maintenance_request(),
        "plan": None,
        "issue_assessment": None,
        "urgency_assessment": None,
        "information_review": None,
        "coordination_recommendation": None,
        "final_summary": None,
        "execution_steps": [],
        "delegated_roles": [],
    }

    state["execution_steps"] = ["plan", "classify_assess_issue", "assess_urgency", "review_maintenance_information", "produce_coordination_recommendation", "summarize"]
    state["delegated_roles"] = [
        "MaintenanceAssessmentAgent",
        "UrgencyRiskAgent",
        "MaintenanceCoordinationAgent",
    ]
    assert state["execution_steps"] == [
        "plan",
        "classify_assess_issue",
        "assess_urgency",
        "review_maintenance_information",
        "produce_coordination_recommendation",
        "summarize",
    ]
    assert state["delegated_roles"] == [
        "MaintenanceAssessmentAgent",
        "UrgencyRiskAgent",
        "MaintenanceCoordinationAgent",
    ]


def test_maintenance_roles_validate_structured_outputs() -> None:
    assessment = MaintenanceAssessmentAgent(provider=None, timeout_seconds=1.0, agent_version="test")
    urgency = UrgencyRiskAgent(provider=None, timeout_seconds=1.0, agent_version="test")
    coordination = MaintenanceCoordinationAgent(provider=None, timeout_seconds=1.0, agent_version="test")

    assert assessment.input_contract == {"maintenance_request": dict}
    assert urgency.input_contract == {"maintenance_request": dict, "issue_assessment": MaintenanceIssueAssessment}
    assert coordination.input_contract == {
        "maintenance_request": dict,
        "issue_assessment": MaintenanceIssueAssessment,
        "urgency_assessment": MaintenanceUrgencyAssessment,
        "information_review": MaintenanceInformationReview,
    }

    assert assessment.output_contract is MaintenanceIssueAssessment
    assert urgency.output_contract is MaintenanceUrgencyAssessment
    assert coordination.output_contract is MaintenanceCoordinationRecommendation
    assert MaintenanceCoordinationSummary.model_fields["recommended_category"].alias == "recommendedCategory"


def test_maintenance_roles_do_not_mutate_authoritative_state() -> None:
    request = valid_maintenance_request()
    state = {
        "maintenance_request": request,
        "plan": None,
        "issue_assessment": None,
        "urgency_assessment": None,
        "information_review": None,
        "coordination_recommendation": None,
        "final_summary": None,
        "execution_steps": [],
        "delegated_roles": [],
    }

    original = {"maintenanceRequestId": request["maintenanceRequestId"], "title": request["title"]}
    before = state["maintenance_request"].copy()

    assessment = MaintenanceAssessmentAgent(provider=None, timeout_seconds=1.0, agent_version="test")
    assessment._assert_no_mutation(state, before)

    assert state["maintenance_request"]["maintenanceRequestId"] == original["maintenanceRequestId"]
    assert state["maintenance_request"]["title"] == original["title"]


def test_provider_failure_is_sanitized(settings) -> None:
    from app.main import create_app

    response = TestClient(
        create_app(settings=settings, model_provider=FailingMaintenanceProvider()),
        raise_server_exceptions=False,
    ).post("/internal/maintenance-coordination/analyze", json=valid_maintenance_request())

    assert response.status_code == 502
    assert response.json()["error"]["code"] == "model_invocation_failed"
    assert "maintenance-provider-secret" not in response.text


def test_malformed_model_output_is_rejected(settings) -> None:
    provider = MaintenanceProvider({"MaintenancePlan": {"steps": ["unsafe_step"]}})
    from app.main import create_app

    response = TestClient(create_app(settings=settings, model_provider=provider)).post(
        "/internal/maintenance-coordination/analyze",
        json=valid_maintenance_request(),
    )

    assert response.status_code == 502
    assert response.json()["error"]["code"] == "invalid_model_output"


def test_missing_maintenance_information_is_returned_as_warning(settings) -> None:
    request = valid_maintenance_request()
    request.pop("repairEstimate")
    request.pop("assignedTechnicianId")
    provider = MaintenanceProvider()
    from app.main import create_app

    response = TestClient(create_app(settings=settings, model_provider=provider)).post(
        "/internal/maintenance-coordination/analyze",
        json=request,
    )

    assert response.status_code == 200
    assert "No repair estimate was supplied." in response.json()["result"]["warnings"]