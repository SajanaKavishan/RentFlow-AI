"""Strict request models for data supplied by the ASP.NET Core API."""

from __future__ import annotations

from typing import Any, Literal

from pydantic import AliasChoices, Field, field_validator

from app.schemas.common import StrictModel, reject_sensitive_input_keys
from app.schemas.supporting_documents import SupportingDocumentInput


class DocumentMetadata(StrictModel):
    document_id: str = Field(
        min_length=1,
        max_length=200,
        validation_alias=AliasChoices("documentId", "document_id"),
        serialization_alias="documentId",
    )
    document_type: str = Field(
        min_length=1,
        max_length=100,
        validation_alias=AliasChoices("documentType", "document_type"),
        serialization_alias="documentType",
    )
    file_name: str | None = Field(
        default=None,
        max_length=255,
        validation_alias=AliasChoices("fileName", "file_name"),
        serialization_alias="fileName",
    )
    is_required: bool = Field(
        default=False,
        validation_alias=AliasChoices("isRequired", "is_required"),
        serialization_alias="isRequired",
    )


class DeterministicFinding(StrictModel):
    code: str = Field(min_length=1, max_length=100)
    severity: Literal["info", "warning", "error"]
    message: str = Field(min_length=1, max_length=1000)
    field: str | None = Field(default=None, max_length=100)


class ApplicationValidationRequest(StrictModel):
    workflow_id: str = Field(
        min_length=1,
        max_length=200,
        validation_alias=AliasChoices("workflowId", "workflow_id"),
        serialization_alias="workflowId",
    )
    application_id: str = Field(
        min_length=1,
        max_length=200,
        validation_alias=AliasChoices("applicationId", "application_id"),
        serialization_alias="applicationId",
    )
    objective: str = Field(min_length=1, max_length=1000)
    application_data: dict[str, Any] = Field(
        validation_alias=AliasChoices("applicationData", "application_data"),
        serialization_alias="applicationData",
    )
    document_metadata: list[DocumentMetadata] = Field(
        max_length=100,
        validation_alias=AliasChoices("documentMetadata", "document_metadata"),
        serialization_alias="documentMetadata",
    )
    deterministic_findings: list[DeterministicFinding] = Field(
        max_length=200,
        validation_alias=AliasChoices("deterministicFindings", "deterministic_findings"),
        serialization_alias="deterministicFindings",
    )
    supporting_documents: list[SupportingDocumentInput] = Field(
        default_factory=list,
        max_length=100,
        validation_alias=AliasChoices("supportingDocuments", "supporting_documents"),
        serialization_alias="supportingDocuments",
    )

    @field_validator("application_data")
    @classmethod
    def application_data_must_be_safe_json(cls, value: dict[str, Any]) -> dict[str, Any]:
        reject_sensitive_input_keys(value)
        return value
