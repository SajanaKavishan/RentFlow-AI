"""State definition for the property matching LangGraph."""

from __future__ import annotations

from typing import Any, TypedDict


class PropertyMatchingAgentState(TypedDict):
    preferences: dict[str, Any]
    candidates: list[dict[str, Any]]

    plan: dict[str, Any] | None
    match_analysis: dict[str, Any] | None
    final_summary: dict[str, Any] | None

    execution_steps: list[str]