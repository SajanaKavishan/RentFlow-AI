from __future__ import annotations

import logging

from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app
from app.services.model_provider import build_model_provider
from tests.conftest import FakeModelProvider, valid_request


class FailingModelProvider(FakeModelProvider):
    async def generate_structured(self, **kwargs):
        del kwargs
        raise RuntimeError("secret-provider-detail-must-not-escape")


def test_health_endpoint(client: TestClient) -> None:
    response = client.get("/health")

    assert response.status_code == 200
    assert response.json() == {"status": "healthy"}


def test_request_schema_rejects_unknown_fields(client: TestClient) -> None:
    payload = valid_request()
    payload["databaseConnectionString"] = "postgresql://should-not-be-accepted"

    response = client.post("/internal/application-validation/analyze", json=payload)

    assert response.status_code == 422


def test_invalid_workflow_data_is_rejected(client: TestClient) -> None:
    payload = valid_request()
    payload["workflowId"] = ""

    response = client.post("/internal/application-validation/analyze", json=payload)

    assert response.status_code == 422


def test_sensitive_input_fields_are_rejected(client: TestClient) -> None:
    payload = valid_request()
    payload["applicationData"]["riskScore"] = 91

    response = client.post("/internal/application-validation/analyze", json=payload)

    assert response.status_code == 422


def test_provider_not_configured_returns_safe_failure(settings: Settings) -> None:
    provider = build_model_provider(settings)
    client = TestClient(create_app(settings=settings, model_provider=provider))

    response = client.post("/internal/application-validation/analyze", json=valid_request())

    assert response.status_code == 503
    assert response.json() == {
        "error": {
            "code": "provider_not_configured",
            "message": "AI analysis is not configured for this service.",
            "retryable": False,
        }
    }
    assert "traceback" not in response.text.lower()


def test_unsupported_provider_does_not_break_startup(settings: Settings) -> None:
    configured = Settings(
        ai_provider="unsupported",
        ai_model="model",
        ai_api_key="test-key",
        ai_timeout_seconds=settings.ai_timeout_seconds,
        agent_version=settings.agent_version,
    )
    client = TestClient(create_app(settings=configured))

    assert client.get("/health").json() == {"status": "healthy"}
    response = client.post("/internal/application-validation/analyze", json=valid_request())
    assert response.status_code == 503
    assert response.json()["error"]["code"] == "unsupported_provider"


def test_malformed_model_output_returns_safe_failure(settings: Settings) -> None:
    provider = FakeModelProvider({"Plan": {"steps": ["invent_a_tool"]}})
    client = TestClient(create_app(settings=settings, model_provider=provider))

    response = client.post("/internal/application-validation/analyze", json=valid_request())

    assert response.status_code == 502
    assert response.json()["error"]["code"] == "invalid_model_output"
    assert "invent_a_tool" not in response.text
    assert "traceback" not in response.text.lower()


def test_model_failure_returns_sanitized_error(settings: Settings) -> None:
    client = TestClient(
        create_app(settings=settings, model_provider=FailingModelProvider()),
        raise_server_exceptions=False,
    )

    response = client.post("/internal/application-validation/analyze", json=valid_request())

    assert response.status_code == 502
    assert response.json()["error"]["code"] == "model_invocation_failed"
    assert "secret-provider-detail" not in response.text


def test_graph_runs_nodes_in_fixed_order(
    client: TestClient,
    fake_provider: FakeModelProvider,
    caplog,
) -> None:
    with caplog.at_level(logging.DEBUG, logger="app.services.model_provider"):
        response = client.post("/internal/application-validation/analyze", json=valid_request())

    assert response.status_code == 200
    body = response.json()
    assert body["workflowId"] == "workflow-123"
    assert body["result"]["requiresHumanApproval"] is True
    assert body["result"]["agentVersion"] == "test-1.0"
    assert body["executionMetadata"]["executedSteps"] == [
        "plan",
        "analyze_application_data",
        "analyze_document_metadata",
        "analyze_consistency",
        "summarize_findings",
    ]
    assert fake_provider.calls == [
        "Plan",
        "ApplicationDataAnalysis",
        "DocumentAnalysis",
        "ConsistencyAnalysis",
        "FinalAgentSummary",
    ]
    for node_name in (
        "planner",
        "application_data_analysis",
        "document_analysis",
        "consistency_analysis",
        "final_summary",
    ):
        assert f"event=model_invocation_started node={node_name}" in caplog.text
        assert f"event=model_invocation_succeeded node={node_name}" in caplog.text
