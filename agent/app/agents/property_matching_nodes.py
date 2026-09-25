"""Structured LangGraph nodes for advisory property matching."""

from __future__ import annotations

from typing import Any, Awaitable, Callable

from app.graph.property_matching_state import PropertyMatchingAgentState
from app.schemas.property_matching import (
    PropertyMatchingSummary,
    PropertyMatchRecommendation,
)
from app.services.model_provider import ModelProvider, request_structured_output


Node = Callable[
    [PropertyMatchingAgentState],
    Awaitable[dict[str, Any]],
]


_ADVISORY_SAFETY = (
    "This agent is advisory only. "
    "Use only the supplied tenant preferences and property candidates. "
    "Never invent properties, prices, amenities, or property IDs. "
    "Never modify property data or database state."
)


def create_property_matching_nodes(
    provider: ModelProvider,
    *,
    timeout_seconds: float,
    agent_version: str,
) -> dict[str, Node]:
    """Create the nodes used by the property matching workflow."""

    async def plan(
        state: PropertyMatchingAgentState,
    ) -> dict[str, Any]:
        """Create the fixed property matching execution plan."""

        return {
            "plan": {
                "steps": [
                    "analyze_matches",
                    "summarize",
                ]
            },
            "execution_steps": ["plan"],
        }

    async def analyze_matches(
        state: PropertyMatchingAgentState,
    ) -> dict[str, Any]:
        """
        Ask the model to rank and explain the supplied property candidates.

        Match scores are calculated deterministically by the backend.
        The model is not allowed to calculate authoritative scores.
        """

        output = await request_structured_output(
            provider,
            output_schema=PropertyMatchingSummary,
            instructions=(
                "Analyze and rank the supplied rental property candidates "
                "against the tenant preferences. "
                "Each candidate already contains a deterministic matchScore "
                "and matchReasons calculated by the backend. "
                "You MUST copy each candidate's matchScore exactly. "
                "Never calculate, modify, increase, decrease, or invent "
                "a matchScore. "
                "Use the supplied matchReasons and property data to explain "
                "why the strongest properties are good matches. "
                "Only recommend properties contained in the supplied "
                "candidates. "
                "Never invent property IDs, prices, amenities, bedrooms, "
                "bathrooms, or other property information. "
                f"Set agentVersion to '{agent_version}'. "
                f"{_ADVISORY_SAFETY}"
            ),
            input_data={
                "preferences": state["preferences"],
                "candidates": state["candidates"],
            },
            timeout_seconds=timeout_seconds,
            invocation_name="property_matching_analysis",
        )

        return {
            "match_analysis": output.model_dump(
                mode="json",
                by_alias=True,
            ),
            "execution_steps": [
                *state["execution_steps"],
                "analyze_matches",
            ],
        }

    async def summarize(
        state: PropertyMatchingAgentState,
    ) -> dict[str, Any]:
        """
        Validate the AI response against the original candidates.

        Property IDs must exist in the supplied candidate list and
        deterministic match scores are restored from the original
        candidate data regardless of what the model returned.
        """

        analysis = PropertyMatchingSummary.model_validate(
            state["match_analysis"]
        )

        candidates_by_id = {
            str(
                candidate.get("propertyId")
                or candidate.get("property_id")
            ): candidate
            for candidate in state["candidates"]
        }

        validated_matches: list[PropertyMatchRecommendation] = []

        for match in analysis.matches:
            candidate = candidates_by_id.get(match.property_id)

            if candidate is None:
                raise ValueError(
                    "Agent returned unknown property ID: "
                    f"{match.property_id}"
                )

            authoritative_score = candidate.get(
                "matchScore",
                candidate.get("match_score"),
            )

            if authoritative_score is None:
                raise ValueError(
                    "Candidate "
                    f"{match.property_id} "
                    "has no deterministic match score."
                )

            validated_match = (
                PropertyMatchRecommendation.model_validate(
                    {
                        "propertyId": match.property_id,
                        "matchScore": authoritative_score,
                        "reasons": match.reasons,
                    }
                )
            )

            validated_matches.append(validated_match)

        summary = PropertyMatchingSummary.model_validate(
            {
                "matches": [
                    match.model_dump(
                        mode="json",
                        by_alias=True,
                    )
                    for match in validated_matches
                ],
                "summary": analysis.summary,
                "agentVersion": agent_version,
            }
        )

        return {
            "final_summary": summary.model_dump(
                mode="json",
                by_alias=True,
            ),
            "execution_steps": [
                *state["execution_steps"],
                "summarize",
            ],
        }

    return {
        "plan": plan,
        "analyze_matches": analyze_matches,
        "summarize": summarize,
    }