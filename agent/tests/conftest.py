from __future__ import annotations

import socket
from collections.abc import Callable
from typing import Any

import pytest
from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app
from app.services.model_provider import ModelProvider


class FakeModelProvider(ModelProvider):
    def __init__(self, responses: dict[str, Any] | None = None) -> None:
        self.responses = responses or valid_model_responses()
        self.calls: list[str] = []

    async def generate_structured(
        self,
        *,
        output_schema,
        instructions: str,
        input_data: dict[str, Any],
    ) -> Any:
        del instructions, input_data
        schema_name = output_schema.__name__
        self.calls.append(schema_name)
        response = self.responses[schema_name]
        return response() if callable(response) else response


def valid_model_responses() -> dict[str, Any]:
    return {
        "Plan": {
            "steps": [
                "analyze_application_data",
                "analyze_document_metadata",
                "analyze_consistency",
                "summarize_findings",
            ]
        },
        "ApplicationDataAnalysis": {
            "completeness_findings": [],
            "inconsistency_findings": [],
            "explanation": "The supplied application fields are complete for this review.",
        },
        "DocumentAnalysis": {
            "covered_document_types": ["proof_of_income"],
            "missing_document_types": [],
            "duplicate_document_types": [],
            "findings": [],
            "explanation": "The supplied metadata contains one supporting document.",
        },
        "ConsistencyAnalysis": {
            "consistent": True,
            "findings": [],
            "explanation": "No contradiction is visible in the supplied structured data.",
        },
        "FinalAgentSummary": {
            "recommendation": "Ready for landlord review",
            "summary": "The application is ready for a landlord's manual review.",
            "key_findings": ["No deterministic blocking findings were supplied."],
            "warnings": [],
            "requires_human_approval": True,
            "agent_version": "model-supplied-value-is-overridden",
        },
    }


def valid_request() -> dict[str, Any]:
    return {
        "workflowId": "workflow-123",
        "applicationId": "application-456",
        "objective": "Summarize the application for landlord review.",
        "applicationData": {"employmentStatus": "employed", "monthlyIncome": 5000},
        "documentMetadata": [
            {
                "documentId": "document-789",
                "documentType": "proof_of_income",
                "fileName": "income.pdf",
                "isRequired": True,
            }
        ],
        "deterministicFindings": [],
    }


@pytest.fixture(autouse=True)
def block_external_network(monkeypatch: pytest.MonkeyPatch) -> None:
    original_connect: Callable[..., Any] = socket.socket.connect

    def guarded_connect(sock: socket.socket, address: Any) -> Any:
        host = address[0] if isinstance(address, tuple) else address
        if host not in {"127.0.0.1", "::1", "localhost", "testserver"}:
            raise AssertionError(f"External network access is forbidden in unit tests: {host}")
        return original_connect(sock, address)

    monkeypatch.setattr(socket.socket, "connect", guarded_connect)


@pytest.fixture
def settings() -> Settings:
    return Settings(
        ai_provider=None,
        ai_model=None,
        ai_api_key=None,
        ai_timeout_seconds=1.0,
        agent_version="test-1.0",
    )


@pytest.fixture
def fake_provider() -> FakeModelProvider:
    return FakeModelProvider()


@pytest.fixture
def client(settings: Settings, fake_provider: FakeModelProvider) -> TestClient:
    return TestClient(create_app(settings=settings, model_provider=fake_provider))
