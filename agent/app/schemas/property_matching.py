"""Strict request and structured output models for property matching."""

from __future__ import annotations

from pydantic import AliasChoices, Field

from app.schemas.common import StrictModel


class PropertyPreferences(StrictModel):
    preferred_city: str | None = Field(
        default=None,
        max_length=200,
        validation_alias=AliasChoices("preferredCity", "preferred_city"),
        serialization_alias="preferredCity",
    )

    maximum_monthly_rent: float | None = Field(
        default=None,
        ge=0,
        validation_alias=AliasChoices(
            "maximumMonthlyRent",
            "maximum_monthly_rent",
        ),
        serialization_alias="maximumMonthlyRent",
    )

    minimum_bedrooms: int | None = Field(
        default=None,
        ge=0,
        le=100,
        validation_alias=AliasChoices(
            "minimumBedrooms",
            "minimum_bedrooms",
        ),
        serialization_alias="minimumBedrooms",
    )

    minimum_bathrooms: int | None = Field(
        default=None,
        ge=0,
        le=100,
        validation_alias=AliasChoices(
            "minimumBathrooms",
            "minimum_bathrooms",
        ),
        serialization_alias="minimumBathrooms",
    )

    preferred_amenities: list[str] = Field(
        default_factory=list,
        max_length=100,
        validation_alias=AliasChoices(
            "preferredAmenities",
            "preferred_amenities",
        ),
        serialization_alias="preferredAmenities",
    )


class PropertyCandidate(StrictModel):
    property_id: str = Field(
        min_length=1,
        max_length=200,
        validation_alias=AliasChoices(
            "propertyId",
            "property_id",
        ),
        serialization_alias="propertyId",
    )

    title: str = Field(
        min_length=1,
        max_length=300,
    )

    city: str = Field(
        min_length=1,
        max_length=200,
    )

    monthly_rent: float = Field(
        ge=0,
        validation_alias=AliasChoices(
            "monthlyRent",
            "monthly_rent",
        ),
        serialization_alias="monthlyRent",
    )

    bedrooms: int = Field(
        ge=0,
        le=100,
    )

    bathrooms: int = Field(
        ge=0,
        le=100,
    )

    amenities: list[str] = Field(
        default_factory=list,
        max_length=100,
    )

    # These values are calculated deterministically by ASP.NET.
    # The AI agent must not invent or recalculate them.
    match_score: int = Field(
        ge=0,
        le=100,
        validation_alias=AliasChoices(
            "matchScore",
            "match_score",
        ),
        serialization_alias="matchScore",
    )

    match_reasons: list[str] = Field(
        default_factory=list,
        max_length=20,
        validation_alias=AliasChoices(
            "matchReasons",
            "match_reasons",
        ),
        serialization_alias="matchReasons",
    )


class PropertyMatchingRequest(StrictModel):
    preferences: PropertyPreferences

    candidates: list[PropertyCandidate] = Field(
        max_length=100,
    )


class PropertyMatchRecommendation(StrictModel):
    property_id: str = Field(
        min_length=1,
        max_length=200,
        alias="propertyId",
    )

    match_score: int = Field(
        ge=0,
        le=100,
        alias="matchScore",
    )

    reasons: list[str] = Field(
        min_length=1,
        max_length=20,
    )


class PropertyMatchingSummary(StrictModel):
    matches: list[PropertyMatchRecommendation] = Field(
        max_length=100,
    )

    summary: str = Field(
        min_length=1,
        max_length=3000,
    )

    agent_version: str = Field(
        min_length=1,
        max_length=100,
        alias="agentVersion",
    )


class PropertyMatchingExecutionMetadata(StrictModel):
    executed_steps: list[str] = Field(
        min_length=3,
        max_length=3,
        alias="executedSteps",
    )


class PropertyMatchingResponse(StrictModel):
    result: PropertyMatchingSummary

    execution_metadata: PropertyMatchingExecutionMetadata = Field(
        alias="executionMetadata",
    )