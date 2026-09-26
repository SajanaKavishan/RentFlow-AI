"""JSON-serializable state for the fixed pricing analysis graph."""

from __future__ import annotations

from typing import Any, TypedDict


class PricingAnalysisAgentState(TypedDict):
    request: dict[str, Any]
    plan: list[str] | None
    property_facts: dict[str, Any] | None
    comparables: list[dict[str, Any]] | None
    analysis_draft: dict[str, Any] | None
    validated_draft: dict[str, Any] | None
    validation_findings: list[str]
    execution_steps: list[str]
    skipped_steps: list[str]
    response: dict[str, Any] | None
