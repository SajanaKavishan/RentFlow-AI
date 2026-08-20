from __future__ import annotations

import base64
import pytest
from pydantic import ValidationError

from app.schemas.analysis import FinalAgentSummary
from app.schemas.requests import ApplicationValidationRequest
from app.schemas.supporting_documents import (
    MAX_SUPPORTING_DOCUMENT_BYTES,
    CrossDocumentConsistencyFinding,
    CrossDocumentConsistencyResult,
    SupportingDocumentExtractedFacts,
    SupportingDocumentInput,
    SupportingDocumentVerificationResult,
)
from app.services.supporting_document_verification import (
    DeterministicCrossDocumentConsistencyAnalyzer,
)


def _input(**overrides):
    content = overrides.pop("content", b"phase-a")
    values = {
        "documentId": "document-1",
        "documentType": "IncomeProof",
        "originalFileName": "evidence.pdf",
        "contentType": "application/pdf",
        "sizeBytes": len(content),
        "contentBase64": base64.b64encode(content).decode("ascii"),
    }
    values.update(overrides)
    return values


@pytest.mark.parametrize("content_type", ["application/pdf", "image/jpeg", "image/png"])
def test_valid_supported_document_content_is_accepted(content_type: str) -> None:
    model = SupportingDocumentInput.model_validate(_input(contentType=content_type))

    assert model.content_type == content_type


def test_malformed_base64_is_rejected() -> None:
    with pytest.raises(ValidationError):
        SupportingDocumentInput.model_validate(_input(contentBase64="not;base64!"))


def test_oversized_decoded_payload_is_rejected() -> None:
    oversized = b"x" * (MAX_SUPPORTING_DOCUMENT_BYTES + 1)

    with pytest.raises(ValidationError):
        SupportingDocumentInput.model_validate(_input(content=oversized))


def test_unsupported_mime_is_rejected() -> None:
    with pytest.raises(ValidationError):
        SupportingDocumentInput.model_validate(_input(contentType="text/plain"))


def test_unknown_document_input_field_is_rejected() -> None:
    with pytest.raises(ValidationError):
        SupportingDocumentInput.model_validate(_input(storageKey="private-key"))


def test_application_request_accepts_only_the_safe_document_contract() -> None:
    request = ApplicationValidationRequest.model_validate(
        {
            "workflowId": "workflow-1",
            "applicationId": "application-1",
            "objective": "Prepare a structured manual review.",
            "applicationData": {},
            "documentMetadata": [],
            "deterministicFindings": [],
            "supportingDocuments": [_input()],
        }
    )

    document_json = request.supporting_documents[0].model_dump(mode="json", by_alias=True)
    assert set(document_json) == {
        "documentId",
        "documentType",
        "originalFileName",
        "contentType",
        "sizeBytes",
        "contentBase64",
    }


def test_sensitive_identity_fields_are_absent_and_nonidentity_facts_are_rejected() -> None:
    prohibited = {
        "nic_number",
        "passport_number",
        "birth_certificate_number",
        "date_of_birth",
        "gender",
        "religion",
        "ethnicity",
        "disability",
        "facial_attributes",
        "health_data",
        "political_affiliation",
        "sexual_orientation",
        "parent_details",
    }
    assert prohibited.isdisjoint(SupportingDocumentExtractedFacts.model_fields)

    with pytest.raises(ValidationError):
        SupportingDocumentVerificationResult(
            document_id="identity-1",
            document_type="IdentityDocument",
            readable=True,
            detected_document_category="IdentityDocument",
            extracted_facts=SupportingDocumentExtractedFacts(employer_name="Not allowed"),
            confidence_label="Low",
        )


def test_score_fields_are_absent_from_verification_and_consistency_schemas() -> None:
    prohibited = {"risk_score", "fraud_score", "tenant_score", "trust_score"}
    for model in (
        SupportingDocumentVerificationResult,
        CrossDocumentConsistencyFinding,
        CrossDocumentConsistencyResult,
        FinalAgentSummary,
    ):
        assert prohibited.isdisjoint(model.model_fields)


@pytest.mark.parametrize(
    "comparison",
    [
        "occupation_vs_job_title",
        "monthly_income_vs_income_amount",
        "applicant_name_consistency",
        "employer_name_consistency",
        "document_category_vs_uploaded_type",
    ],
)
def test_consistency_schema_supports_only_allowed_comparisons(comparison: str) -> None:
    finding = CrossDocumentConsistencyFinding(
        comparison=comparison,
        message="Structured comparison requires manual review.",
    )
    assert finding.comparison == comparison


@pytest.mark.asyncio
async def test_empty_consistency_analysis_is_deterministic_and_requires_no_network() -> None:
    analyzer = DeterministicCrossDocumentConsistencyAnalyzer()

    consistency = await analyzer.analyze({}, [])

    assert consistency.matched_facts == []
    assert consistency.mismatches == []
    assert consistency.requires_manual_review is False
