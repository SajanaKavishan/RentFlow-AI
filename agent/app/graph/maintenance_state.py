"""JSON-serializable state for the maintenance coordination graph."""

from __future__ import annotations

from typing import Any, TypedDict


class MaintenanceCoordinationAgentState(TypedDict):
    maintenance_request: dict[str, Any]
    plan: dict[str, Any] | None
    issue_assessment: dict[str, Any] | None
    urgency_assessment: dict[str, Any] | None
    information_review: dict[str, Any] | None
    coordination_recommendation: dict[str, Any] | None
    final_summary: dict[str, Any] | None
    execution_steps: list[str]