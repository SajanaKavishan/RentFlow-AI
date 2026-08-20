"""Validated structured outputs for every graph analysis node."""

from __future__ import annotations

from enum import Enum

from pydantic import Field, field_validator

from app.schemas.common import Finding, StrictModel
from app.schemas.supporting_documents import (
    CrossDocumentConsistencyResult,
    SupportingDocumentVerificationResult,
)


class ApplicationDataAnalysis(StrictModel):
    completeness_findings: list[Finding] = Field(default_factory=list, max_length=100)
    inconsistency_findings: list[Finding] = Field(default_factory=list, max_length=100)
    explanation: str = Field(min_length=1, max_length=2000)


class DocumentAnalysis(StrictModel):
    covered_document_types: list[str] = Field(default_factory=list, max_length=100)
    missing_document_types: list[str] = Field(default_factory=list, max_length=100)
    duplicate_document_types: list[str] = Field(default_factory=list, max_length=100)
    findings: list[Finding] = Field(default_factory=list, max_length=100)
    explanation: str = Field(min_length=1, max_length=2000)


class ConsistencyAnalysis(StrictModel):
    consistent: bool
    findings: list[Finding] = Field(default_factory=list, max_length=100)
    explanation: str = Field(min_length=1, max_length=2000)


class Recommendation(str, Enum):
    READY_FOR_LANDLORD_REVIEW = "Ready for landlord review"
    REQUEST_MISSING_INFORMATION = "Request missing information"
    REQUEST_MISSING_DOCUMENTS = "Request missing documents"
    MANUAL_REVIEW_REQUIRED = "Manual review required"


class FinalAgentSummaryDraft(StrictModel):
    """Only fields the text model owns; deterministic results are service-owned."""

    # Provider JSON represents enum values as strings; the enum still rejects all unknown values.
    recommendation: Recommendation = Field(strict=False)
    summary: str = Field(min_length=1, max_length=2000)
    key_findings: list[str] = Field(
        default_factory=list,
        max_length=100,
        alias="keyFindings",
    )
    warnings: list[str] = Field(default_factory=list, max_length=100)
    requires_human_approval: bool = Field(alias="requiresHumanApproval")

    @field_validator("requires_human_approval")
    @classmethod
    def human_approval_is_mandatory(cls, value: bool) -> bool:
        if value is not True:
            raise ValueError("requiresHumanApproval must always be true")
        return value


class FinalAgentSummary(FinalAgentSummaryDraft):
    agent_version: str = Field(min_length=1, max_length=100, alias="agentVersion")
    supporting_document_verification: list[SupportingDocumentVerificationResult] = Field(
        default_factory=list,
        max_length=100,
        alias="supportingDocumentVerification",
    )
    cross_document_consistency: CrossDocumentConsistencyResult = Field(
        default_factory=lambda: CrossDocumentConsistencyResult(requires_manual_review=True),
        alias="crossDocumentConsistency",
    )
