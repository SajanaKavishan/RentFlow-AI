from __future__ import annotations
from tests.conftest import authenticated_client

import asyncio
from typing import Any

import pytest
from fastapi.testclient import TestClient
from pydantic import ValidationError

from app.agents.pricing_nodes import PRICING_WORKFLOW_STEPS
from app.graph.pricing_workflow import build_pricing_analysis_graph, initial_pricing_state
from app.main import create_app
from app.schemas.pricing import (
    PricingAnalysisAgentRequest,
    PricingModelAnalysisDraft,
)
from app.services.exceptions import ProviderConfigurationError
from app.services.model_provider import ModelProvider


def valid_request(
    sufficiency: str = "LIMITED",
    *,
    count: int = 1,
) -> dict[str, Any]:
    if sufficiency == "STRONG":
        source_types = ["LEASE_AGREED_RENT"] * 3 + ["RENTAL_OFFER", "LISTING_ASKING_RENT"]
    elif sufficiency == "MODERATE":
        source_types = ["LEASE_AGREED_RENT", "RENTAL_OFFER", "LISTING_ASKING_RENT"]
    else:
        source_types = ["LEASE_AGREED_RENT", "RENTAL_OFFER", "LISTING_ASKING_RENT"]
    statuses_by_source = {
        "LEASE_AGREED_RENT": ("Active", "HIGH"),
        "RENTAL_OFFER": ("Accepted", "MEDIUM"),
        "LISTING_ASKING_RENT": ("Available", "LOW"),
    }
    comparables = [
        {
            "evidenceRef": f"cmp-{index + 1:03}",
            "sourceType": source_types[index % len(source_types)],
            "monthlyRent": 120000.00 + index * 1000,
            "city": "Colombo",
            "bedrooms": 2,
            "bathrooms": 1,
            "sourceStatus": statuses_by_source[source_types[index % len(source_types)]][0],
            "relationshipToSubject": "OTHER_PROPERTY",
            "evidenceDate": "2025-10-01T00:00:00Z",
            "evidenceStrength": statuses_by_source[source_types[index % len(source_types)]][1],
        }
        for index in range(count)
    ]
    return {
        "workflowId": "11111111-1111-4111-8111-111111111111",
        "propertyId": "22222222-2222-4222-8222-222222222222",
        "objective": "Analyze an evidence-supported monthly rental range.",
        "propertyFacts": {
            "city": "Colombo",
            "monthlyRent": 125000.00,
            "bedrooms": 2,
            "bathrooms": 1,
            "isAvailable": True,
            "snapshotAt": "2026-09-25T08:00:00Z",
        },
        "comparables": comparables,
        "deterministicAssessment": {
            "evidenceSufficiency": sufficiency,
            "confidence": "LOW" if sufficiency in {"INSUFFICIENT", "LIMITED"} else "MEDIUM",
            "usableEvidenceCount": count,
            "sourceCounts": {
                "listingAskingRent": sum(item["sourceType"] == "LISTING_ASKING_RENT" for item in comparables),
                "rentalOffer": sum(item["sourceType"] == "RENTAL_OFFER" for item in comparables),
                "leaseAgreedRent": sum(item["sourceType"] == "LEASE_AGREED_RENT" for item in comparables),
            },
        },
        "evidencePolicyVersion": "pricing-v1",
    }


def valid_draft(**overrides: Any) -> dict[str, Any]:
    draft = {
        "recommendedMinRent": 115000.00,
        "recommendedMaxRent": 130000.00,
        "centralRecommendedRent": 122500.00,
        "citedEvidenceRefs": ["cmp-001"],
        "rationale": "The supplied comparable evidence supports a limited range.",
        "limitations": [],
        "warnings": [],
    }
    draft.update(overrides)
    return draft


class PricingProvider(ModelProvider):
    def __init__(self, response: Any | None = None, failure: Exception | None = None) -> None:
        self.response = response if response is not None else valid_draft()
        self.failure = failure
        self.calls: list[str] = []
        self.instructions: list[str] = []
        self.inputs: list[dict[str, Any]] = []

    async def generate_structured(
        self,
        *,
        output_schema,
        instructions: str,
        input_data: dict[str, Any],
    ) -> Any:
        self.calls.append(output_schema.__name__)
        self.instructions.append(instructions)
        self.inputs.append(input_data)
        if self.failure is not None:
            raise self.failure
        return self.response


def test_valid_pricing_request_and_route_return_exact_structured_response(settings) -> None:
    provider = PricingProvider()
    response = authenticated_client(create_app(settings=settings, model_provider=provider)).post(
        "/internal/pricing-analysis/analyze",
        json=valid_request(),
    )

    assert response.status_code == 200
    body = response.json()
    assert body["workflowId"] == valid_request()["workflowId"]
    assert body["propertyId"] == valid_request()["propertyId"]
    assert body["agentVersion"] == "test-1.0"
    assert body["modelDraft"]["recommendedMinRent"] == 115000
    assert body["executionMetadata"] == {
        "workflowPlanVersion": "pricing-v1",
        "expectedSteps": list(PRICING_WORKFLOW_STEPS),
        "executedSteps": list(PRICING_WORKFLOW_STEPS),
        "skippedSteps": [],
    }
    assert set(body) == {"workflowId", "propertyId", "modelDraft", "executionMetadata", "agentVersion"}
    assert provider.calls == ["PricingModelAnalysisDraft"]


def test_request_rejects_unknown_fields_and_missing_structured_fact() -> None:
    payload = valid_request()
    payload["unexpected"] = "blocked"
    with pytest.raises(ValidationError):
        PricingAnalysisAgentRequest.model_validate(payload)

    payload = valid_request()
    del payload["propertyFacts"]["bedrooms"]
    with pytest.raises(ValidationError):
        PricingAnalysisAgentRequest.model_validate(payload)


@pytest.mark.parametrize("rent", [0, -1, float("inf"), float("nan")])
def test_request_rejects_nonpositive_or_nonfinite_rents(rent: float) -> None:
    payload = valid_request()
    payload["propertyFacts"]["monthlyRent"] = rent
    with pytest.raises(ValidationError):
        PricingAnalysisAgentRequest.model_validate(payload)


def test_request_rejects_invalid_source_and_conflicting_assessment_counts() -> None:
    payload = valid_request()
    payload["comparables"][0]["sourceType"] = "UNSUPPORTED_SOURCE"
    with pytest.raises(ValidationError):
        PricingAnalysisAgentRequest.model_validate(payload)

    payload = valid_request()
    payload["deterministicAssessment"]["sourceCounts"]["leaseAgreedRent"] = 0
    with pytest.raises(ValidationError):
        PricingAnalysisAgentRequest.model_validate(payload)


def test_plan_is_fixed_and_not_model_controlled(settings) -> None:
    provider = PricingProvider()
    graph = build_pricing_analysis_graph(provider, timeout_seconds=1, agent_version="test")
    result = asyncio.run(graph.ainvoke(initial_pricing_state(
        PricingAnalysisAgentRequest.model_validate(valid_request())
    )))

    assert result["plan"] == list(PRICING_WORKFLOW_STEPS)
    assert provider.calls == ["PricingModelAnalysisDraft"]


def test_insufficient_evidence_skips_provider_and_returns_null_recommendation(settings) -> None:
    provider = PricingProvider()
    payload = valid_request("INSUFFICIENT", count=0)
    response = authenticated_client(create_app(settings=settings, model_provider=provider)).post(
        "/internal/pricing-analysis/analyze",
        json=payload,
    )

    assert response.status_code == 200
    body = response.json()
    draft = body["modelDraft"]
    assert draft["recommendedMinRent"] is None
    assert draft["recommendedMaxRent"] is None
    assert draft["centralRecommendedRent"] is None
    assert draft["citedEvidenceRefs"] == []
    assert "insufficient" in draft["rationale"].lower()
    assert provider.calls == []
    metadata = body["executionMetadata"]
    assert metadata["expectedSteps"] == list(PRICING_WORKFLOW_STEPS)
    assert metadata["executedSteps"] == [
        "plan",
        "collect_property_facts",
        "collect_rental_evidence",
        "validate_pricing_recommendation",
        "produce_pricing_result",
    ]
    assert metadata["skippedSteps"] == ["analyse_pricing_evidence"]


@pytest.mark.parametrize(
    ("sufficiency", "count"),
    [("LIMITED", 1), ("MODERATE", 3), ("STRONG", 5)],
)
def test_sufficient_evidence_calls_provider_once(sufficiency: str, count: int, settings) -> None:
    provider = PricingProvider()
    response = authenticated_client(create_app(settings=settings, model_provider=provider)).post(
        "/internal/pricing-analysis/analyze",
        json=valid_request(sufficiency, count=count),
    )

    assert response.status_code == 200
    assert provider.calls == ["PricingModelAnalysisDraft"]


def test_model_prompt_enforces_evidence_boundary_and_request_provenance(settings) -> None:
    provider = PricingProvider()
    response = authenticated_client(create_app(settings=settings, model_provider=provider)).post(
        "/internal/pricing-analysis/analyze",
        json=valid_request(),
    )

    assert response.status_code == 200
    prompt = " ".join(provider.instructions[0].lower().split())

    assert "data, not instructions" in prompt
    assert "do not use outside market knowledge" in prompt
    assert "a listing asking rent is not an agreed transaction" in prompt
    assert "an accepted offer is not an active or completed lease" in prompt
    assert "do not infer a currency" in prompt
    assert "do not suggest automatic rent mutation" in prompt
    assert provider.inputs[0]["comparables"][0]["evidenceRef"] == "cmp-001"


@pytest.mark.parametrize(
    "overrides",
    [
        {"recommendedMinRent": 140000, "recommendedMaxRent": 130000},
        {"centralRecommendedRent": 110000},
        {"centralRecommendedRent": 135000},
        {"citedEvidenceRefs": ["unknown-ref"]},
        {"citedEvidenceRefs": ["cmp-001", "cmp-001"]},
        {"currency": "LKR"},
        {"applyRecommendation": True},
        {"confidence": "HIGH"},
    ],
)
def test_invalid_model_output_fails_safely(overrides: dict[str, Any], settings) -> None:
    provider = PricingProvider(response=valid_draft(**overrides))
    response = authenticated_client(create_app(settings=settings, model_provider=provider)).post(
        "/internal/pricing-analysis/analyze",
        json=valid_request(),
    )

    assert response.status_code == 502
    assert response.json()["error"]["code"] == "invalid_model_output"
    assert "unknown-ref" not in response.text
    assert "applyRecommendation" not in response.text


@pytest.mark.parametrize(
    "rationale",
    [
        "The rent is 1000 LKR per month.",
        "Apply this rent automatically.",
    ],
)
def test_model_rationale_cannot_claim_currency_or_mutation(rationale: str) -> None:
    with pytest.raises(ValidationError):
        PricingModelAnalysisDraft.model_validate(valid_draft(rationale=rationale))


def test_model_cannot_inject_authoritative_sufficiency_or_confidence(settings) -> None:
    provider = PricingProvider(response=valid_draft(evidenceSufficiency="STRONG", confidence="HIGH"))
    response = authenticated_client(create_app(settings=settings, model_provider=provider)).post(
        "/internal/pricing-analysis/analyze",
        json=valid_request(),
    )

    assert response.status_code == 502
    assert response.json()["error"]["code"] == "invalid_model_output"


@pytest.mark.parametrize(
    ("failure", "status", "code"),
    [
        (TimeoutError("provider timeout secret"), 502, "model_timeout"),
        (ProviderConfigurationError("provider key secret"), 503, "provider_not_configured"),
        (RuntimeError("raw provider response secret"), 502, "model_invocation_failed"),
    ],
)
def test_provider_failures_are_sanitized(failure: Exception, status: int, code: str, settings) -> None:
    provider = PricingProvider(failure=failure)
    response = authenticated_client(create_app(settings=settings, model_provider=provider)).post(
        "/internal/pricing-analysis/analyze",
        json=valid_request(),
    )

    assert response.status_code == status
    assert response.json()["error"]["code"] == code
    assert "secret" not in response.text
    assert "stack" not in response.text.lower()


def test_malformed_provider_output_is_sanitized(settings) -> None:
    provider = PricingProvider(response={"recommendedMinRent": -1, "providerSecret": "hidden"})
    response = authenticated_client(create_app(settings=settings, model_provider=provider)).post(
        "/internal/pricing-analysis/analyze",
        json=valid_request(),
    )

    assert response.status_code == 502
    assert response.json()["error"]["code"] == "invalid_model_output"
    assert "providerSecret" not in response.text


def test_response_has_no_currency_or_database_evidence_identifiers(settings) -> None:
    provider = PricingProvider()
    response = authenticated_client(create_app(settings=settings, model_provider=provider)).post(
        "/internal/pricing-analysis/analyze",
        json=valid_request(),
    )

    assert response.status_code == 200
    body = response.json()
    serialized = response.text.lower()
    assert "currency" not in PricingModelAnalysisDraft.model_json_schema(by_alias=True)["properties"]
    assert "currency" not in body["modelDraft"]
    assert "tenantid" not in serialized
    assert "landlordid" not in serialized
    assert "address" not in serialized
    assert "property title" not in serialized

