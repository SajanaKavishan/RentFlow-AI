"""JSON-serializable LangGraph state contract."""

from __future__ import annotations

from typing import Any, TypedDict


class ApplicationValidationAgentState(TypedDict):
    workflow_id: str
    application_id: str
    objective: str
    application_data: dict[str, Any]
    document_metadata: list[dict[str, Any]]
    deterministic_findings: list[dict[str, Any]]
    supporting_document_inputs: list[dict[str, Any]]
    supporting_document_verification: list[dict[str, Any]]
    cross_document_consistency: dict[str, Any] | None
    plan: dict[str, Any] | None
    data_analysis: dict[str, Any] | None
    document_analysis: dict[str, Any] | None
    consistency_analysis: dict[str, Any] | None
    final_summary: dict[str, Any] | None
    errors: list[dict[str, str]]
    execution_steps: list[str]
