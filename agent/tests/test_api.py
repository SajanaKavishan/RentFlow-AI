from __future__ import annotations

import base64
import logging
from io import BytesIO

from fastapi.testclient import TestClient
from pypdf import PdfWriter
from pypdf.generic import DecodedStreamObject, DictionaryObject, NameObject

from app.config import Settings
from app.main import create_app
from app.services.model_provider import build_model_provider
from tests.conftest import FakeModelProvider, valid_model_responses, valid_request


class FailingModelProvider(FakeModelProvider):
    async def generate_structured(self, **kwargs):
        del kwargs
        raise RuntimeError("secret-provider-detail-must-not-escape")


class SupportingDocumentModelProvider(FakeModelProvider):
    async def generate_structured_with_media(self, **kwargs):
        del kwargs
        return {
            "extractedText": "unique in-memory handwritten Sinhala OCR text " * 3,
            "detectedLanguage": "Sinhala",
            "confidenceLabel": "Low",
            "contentStyle": "Handwritten",
            "warnings": ["uncertain"],
        }


def selectable_pdf(text: str) -> bytes:
    writer = PdfWriter()
    font = DictionaryObject(
        {
            NameObject("/Type"): NameObject("/Font"),
            NameObject("/Subtype"): NameObject("/Type1"),
            NameObject("/BaseFont"): NameObject("/Helvetica"),
        }
    )
    font_ref = writer._add_object(font)
    page = writer.add_blank_page(width=612, height=792)
    page[NameObject("/Resources")] = DictionaryObject(
        {NameObject("/Font"): DictionaryObject({NameObject("/F1"): font_ref})}
    )
    escaped = text.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")
    stream = DecodedStreamObject()
    stream.set_data(f"BT /F1 11 Tf 40 740 Td ({escaped}) Tj ET".encode("latin-1"))
    page[NameObject("/Contents")] = writer._add_object(stream)
    buffer = BytesIO()
    writer.write(buffer)
    return buffer.getvalue()


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
        "verify_supporting_documents",
        "analyze_cross_document_consistency",
        "analyze_consistency",
        "summarize_findings",
    ]
    assert fake_provider.calls == [
        "Plan",
        "ApplicationDataAnalysis",
        "DocumentAnalysis",
        "ConsistencyAnalysis",
        "FinalAgentSummaryDraft",
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


def test_supporting_document_analysis_returns_only_safe_structured_output(
    settings: Settings,
) -> None:
    responses = valid_model_responses()
    responses["SupportingDocumentFactAnalysis"] = {
        "detectedDocumentCategory": "IdentityDocument",
        "extractedFacts": {
            "applicantName": "නිමල් පෙරේරා",
            "incomeAmount": None,
            "payPeriod": None,
            "employerName": None,
            "jobTitle": None,
            "documentDate": None,
        },
        "warnings": [],
        "confidenceLabel": "Low",
    }
    provider = SupportingDocumentModelProvider(responses)
    client = TestClient(
        create_app(
            settings=settings,
            model_provider=provider,
            vision_model_provider=provider,
        )
    )
    payload = valid_request()
    raw_content = b"super-secret-raw-document"
    payload["supportingDocuments"] = [
        {
            "documentId": "identity-1",
            "documentType": "IdentityDocument",
            "originalFileName": "identity.png",
            "contentType": "image/png",
            "sizeBytes": len(raw_content),
            "contentBase64": base64.b64encode(raw_content).decode("ascii"),
        }
    ]

    response = client.post("/internal/application-validation/analyze", json=payload)

    assert response.status_code == 200
    body = response.json()
    verification = body["result"]["supportingDocumentVerification"][0]
    assert body["result"]["recommendation"] == "Manual review required"
    assert verification["confidenceLabel"] == "Low"
    assert verification["requiresManualReview"] is True
    assert verification["extractionMethod"] == "VisionOcr"
    assert payload["supportingDocuments"][0]["contentBase64"] not in response.text
    assert "unique in-memory handwritten Sinhala OCR text" not in response.text
    assert "extractedText" not in response.text


def test_missing_vision_provider_warns_without_failing_workflow(
    settings: Settings,
    fake_provider: FakeModelProvider,
) -> None:
    client = TestClient(create_app(settings=settings, model_provider=fake_provider))
    payload = valid_request()
    raw_content = b"synthetic-image"
    payload["supportingDocuments"] = [
        {
            "documentId": "scan-1",
            "documentType": "IncomeProof",
            "originalFileName": "scan.png",
            "contentType": "image/png",
            "sizeBytes": len(raw_content),
            "contentBase64": base64.b64encode(raw_content).decode("ascii"),
        }
    ]

    response = client.post("/internal/application-validation/analyze", json=payload)

    assert response.status_code == 200
    result = response.json()["result"]
    verification = result["supportingDocumentVerification"][0]
    assert verification["readable"] is False
    assert verification["requiresManualReview"] is True
    assert "Vision analysis is not configured" in " ".join(verification["warnings"])
    assert result["requiresHumanApproval"] is True


def test_income_proof_api_response_is_structured_without_raw_transport_data(
    settings: Settings,
) -> None:
    responses = valid_model_responses()
    responses["SupportingDocumentFactAnalysis"] = {
        "detectedDocumentCategory": "IncomeProof",
        "extractedFacts": {
            "applicantName": "Test Applicant",
            "incomeAmount": "LKR 185,000",
            "payPeriod": "July 2026",
            "employerName": "Example Solutions (Pvt) Ltd",
            "jobTitle": "Software Engineer",
            "documentDate": "01 August 2026",
        },
        "warnings": [],
        "confidenceLabel": "High",
    }
    provider = FakeModelProvider(responses)
    client = TestClient(create_app(settings=settings, model_provider=provider))
    raw_content = selectable_pdf(
        "INCOME PROOF Employee Name Test Applicant Employer Example Solutions Gross "
        "Monthly Income LKR 185,000 Pay Period July 2026 Payment Date 01 August 2026"
    )
    payload = valid_request()
    payload["supportingDocuments"] = [
        {
            "documentId": "income-1",
            "documentType": "IncomeProof",
            "originalFileName": "income-proof.pdf",
            "contentType": "application/pdf",
            "sizeBytes": len(raw_content),
            "contentBase64": base64.b64encode(raw_content).decode("ascii"),
        }
    ]

    response = client.post("/internal/application-validation/analyze", json=payload)

    assert response.status_code == 200
    verification = response.json()["result"]["supportingDocumentVerification"][0]
    assert verification == {
        "documentId": "income-1",
        "documentType": "IncomeProof",
        "readable": True,
        "detectedDocumentCategory": "IncomeProof",
        "extractedFacts": {
            "applicantName": "Test Applicant",
            "incomeAmount": "185000",
            "payPeriod": "July 2026",
            "employerName": "Example Solutions (Pvt) Ltd",
            "jobTitle": None,
            "documentDate": "2026-08-01",
        },
        "warnings": [],
        "confidenceLabel": "High",
        "extractionMethod": "PdfText",
        "requiresManualReview": False,
    }
    assert payload["supportingDocuments"][0]["contentBase64"] not in response.text
    assert "extractedText" not in response.text
    assert "storageKey" not in response.text
