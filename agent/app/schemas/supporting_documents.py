"""Strict, allow-listed schemas for supporting-document verification."""

from __future__ import annotations

import base64
import binascii
from decimal import Decimal
from typing import Literal

from pydantic import AliasChoices, Field, model_validator

from app.schemas.common import StrictModel

MAX_SUPPORTING_DOCUMENT_BYTES = 5 * 1024 * 1024
SupportedDocumentType = Literal["IncomeProof", "EmploymentLetter", "IdentityDocument"]
SupportedContentType = Literal["application/pdf", "image/jpeg", "image/png"]


class SupportingDocumentInput(StrictModel):
    document_id: str = Field(
        min_length=1,
        max_length=200,
        validation_alias=AliasChoices("documentId", "document_id"),
        serialization_alias="documentId",
    )
    document_type: SupportedDocumentType = Field(
        validation_alias=AliasChoices("documentType", "document_type"),
        serialization_alias="documentType",
    )
    original_file_name: str = Field(
        min_length=1,
        max_length=255,
        validation_alias=AliasChoices("originalFileName", "original_file_name"),
        serialization_alias="originalFileName",
    )
    content_type: SupportedContentType = Field(
        validation_alias=AliasChoices("contentType", "content_type"),
        serialization_alias="contentType",
    )
    size_bytes: int = Field(
        gt=0,
        le=MAX_SUPPORTING_DOCUMENT_BYTES,
        validation_alias=AliasChoices("sizeBytes", "size_bytes"),
        serialization_alias="sizeBytes",
    )
    content_base64: str = Field(
        min_length=1,
        max_length=((MAX_SUPPORTING_DOCUMENT_BYTES + 2) // 3) * 4,
        validation_alias=AliasChoices("contentBase64", "content_base64"),
        serialization_alias="contentBase64",
    )

    @model_validator(mode="after")
    def validate_encoded_content(self) -> "SupportingDocumentInput":
        try:
            decoded = base64.b64decode(self.content_base64, validate=True)
        except (binascii.Error, ValueError) as exc:
            raise ValueError("contentBase64 must be valid Base64") from exc
        if len(decoded) > MAX_SUPPORTING_DOCUMENT_BYTES:
            raise ValueError("decoded document exceeds the analysis size limit")
        if len(decoded) != self.size_bytes:
            raise ValueError("sizeBytes must match the decoded content size")
        return self


class SupportingDocumentExtractedFacts(StrictModel):
    applicant_name: str | None = Field(
        default=None, max_length=300, alias="applicantName"
    )
    income_amount: Decimal | None = Field(
        default=None, ge=0, strict=False, alias="incomeAmount"
    )
    pay_period: str | None = Field(
        default=None, max_length=100, alias="payPeriod"
    )
    employer_name: str | None = Field(
        default=None, max_length=300, alias="employerName"
    )
    job_title: str | None = Field(
        default=None, max_length=200, alias="jobTitle"
    )
    document_date: str | None = Field(
        default=None,
        pattern=r"^\d{4}-\d{2}-\d{2}$",
        alias="documentDate",
    )


class SupportingDocumentVerificationResult(StrictModel):
    document_id: str = Field(alias="documentId")
    document_type: SupportedDocumentType = Field(alias="documentType")
    readable: bool
    detected_document_category: Literal[
        "IncomeProof", "EmploymentLetter", "IdentityDocument", "Unknown", "NotAssessed"
    ] = Field(alias="detectedDocumentCategory")
    extracted_facts: SupportingDocumentExtractedFacts = Field(
        default_factory=SupportingDocumentExtractedFacts,
        alias="extractedFacts",
    )
    warnings: list[str] = Field(default_factory=list, max_length=100)
    confidence_label: Literal["Low", "Medium", "High", "NotAssessed"] = Field(
        alias="confidenceLabel"
    )

    @model_validator(mode="after")
    def identity_result_has_only_allowed_facts(self) -> "SupportingDocumentVerificationResult":
        facts = self.extracted_facts
        all_fact_values = (
            facts.applicant_name,
            facts.income_amount,
            facts.pay_period,
            facts.employer_name,
            facts.job_title,
            facts.document_date,
        )
        if not self.readable and any(value is not None for value in all_fact_values):
            raise ValueError("Unreadable documents cannot contain extracted facts")
        if self.document_type == "IdentityDocument" and any(
            value is not None
            for value in (
                facts.income_amount,
                facts.pay_period,
                facts.employer_name,
                facts.job_title,
                facts.document_date,
            )
        ):
            raise ValueError("IdentityDocument may contain only applicantName")
        if self.document_type == "IncomeProof" and facts.job_title is not None:
            raise ValueError("IncomeProof does not allow jobTitle")
        if self.document_type == "EmploymentLetter" and any(
            value is not None for value in (facts.income_amount, facts.pay_period)
        ):
            raise ValueError("EmploymentLetter does not allow incomeAmount or payPeriod")
        return self


AllowedComparison = Literal[
    "occupation_vs_job_title",
    "monthly_income_vs_income_amount",
    "applicant_name_consistency",
    "employer_name_consistency",
    "document_category_vs_uploaded_type",
]


class CrossDocumentConsistencyFinding(StrictModel):
    comparison: AllowedComparison
    message: str = Field(min_length=1, max_length=1000)


class CrossDocumentConsistencyResult(StrictModel):
    matched_facts: list[CrossDocumentConsistencyFinding] = Field(
        default_factory=list, max_length=100, alias="matchedFacts"
    )
    mismatches: list[CrossDocumentConsistencyFinding] = Field(default_factory=list, max_length=100)
    warnings: list[str] = Field(default_factory=list, max_length=100)
    requires_manual_review: bool = Field(alias="requiresManualReview")
