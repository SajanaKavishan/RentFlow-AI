"""Strict contracts for advisory rental-price analysis."""

from __future__ import annotations

import re
from datetime import datetime
from decimal import Decimal, InvalidOperation
from enum import Enum
from typing import Any
from uuid import UUID

from pydantic import AliasChoices, Field, field_serializer, field_validator, model_validator

from app.schemas.common import StrictModel


class PricingEvidenceSourceType(str, Enum):
    LISTING_ASKING_RENT = "LISTING_ASKING_RENT"
    RENTAL_OFFER = "RENTAL_OFFER"
    LEASE_AGREED_RENT = "LEASE_AGREED_RENT"


class PricingEvidenceStrength(str, Enum):
    LOW = "LOW"
    MEDIUM = "MEDIUM"
    HIGH = "HIGH"


class PricingEvidenceSufficiency(str, Enum):
    INSUFFICIENT = "INSUFFICIENT"
    LIMITED = "LIMITED"
    MODERATE = "MODERATE"
    STRONG = "STRONG"


class PricingConfidence(str, Enum):
    LOW = "LOW"
    MEDIUM = "MEDIUM"
    HIGH = "HIGH"


class PricingPropertyFacts(StrictModel):
    city: str = Field(min_length=1, max_length=100)
    monthly_rent: Decimal = Field(
        gt=Decimal("0"),
        max_digits=18,
        decimal_places=2,
        alias="monthlyRent",
    )
    bedrooms: int = Field(ge=0)
    bathrooms: int = Field(ge=0)
    is_available: bool = Field(alias="isAvailable")
    snapshot_at: datetime = Field(alias="snapshotAt")

    @field_validator("monthly_rent", mode="before")
    @classmethod
    def parse_json_decimal(cls, value: Any) -> Decimal:
        return _parse_json_decimal(value, allow_zero=False)

    @field_serializer("monthly_rent", when_used="json")
    def serialize_monthly_rent(self, value: Decimal) -> int | float:
        return _serialize_json_decimal(value)

    @field_validator("snapshot_at", mode="before")
    @classmethod
    def parse_snapshot_datetime(cls, value: Any) -> datetime:
        return _parse_datetime(value)


class PricingComparableEvidence(StrictModel):
    evidence_ref: str = Field(
        min_length=1,
        max_length=40,
        validation_alias=AliasChoices("evidenceRef", "evidence_ref"),
        serialization_alias="evidenceRef",
    )
    source_type: PricingEvidenceSourceType = Field(
        strict=False,
        validation_alias=AliasChoices("sourceType", "source_type"),
        serialization_alias="sourceType",
    )
    monthly_rent: Decimal = Field(
        gt=Decimal("0"),
        max_digits=18,
        decimal_places=2,
        validation_alias=AliasChoices("monthlyRent", "monthly_rent"),
        serialization_alias="monthlyRent",
    )
    city: str = Field(min_length=1, max_length=100)
    bedrooms: int = Field(ge=0)
    bathrooms: int = Field(ge=0)
    source_status: str = Field(
        min_length=1,
        max_length=30,
        validation_alias=AliasChoices("sourceStatus", "source_status"),
        serialization_alias="sourceStatus",
    )
    relationship_to_subject: str = Field(
        validation_alias=AliasChoices("relationshipToSubject", "relationship_to_subject"),
        serialization_alias="relationshipToSubject",
    )
    evidence_date: datetime = Field(
        validation_alias=AliasChoices("evidenceDate", "evidence_date"),
        serialization_alias="evidenceDate",
    )
    evidence_strength: PricingEvidenceStrength = Field(
        strict=False,
        validation_alias=AliasChoices("evidenceStrength", "evidence_strength"),
        serialization_alias="evidenceStrength",
    )

    @field_validator("monthly_rent", mode="before")
    @classmethod
    def parse_json_decimal(cls, value: Any) -> Decimal:
        return _parse_json_decimal(value, allow_zero=False)

    @field_serializer("monthly_rent", when_used="json")
    def serialize_monthly_rent(self, value: Decimal) -> int | float:
        return _serialize_json_decimal(value)

    @field_validator("evidence_date", mode="before")
    @classmethod
    def parse_evidence_datetime(cls, value: Any) -> datetime:
        return _parse_datetime(value)

    @model_validator(mode="after")
    def validate_source_provenance(self) -> "PricingComparableEvidence":
        expected = {
            PricingEvidenceSourceType.LISTING_ASKING_RENT: ("Available", PricingEvidenceStrength.LOW),
            PricingEvidenceSourceType.RENTAL_OFFER: ("Accepted", PricingEvidenceStrength.MEDIUM),
            PricingEvidenceSourceType.LEASE_AGREED_RENT: (
                {"Active", "Completed"},
                PricingEvidenceStrength.HIGH,
            ),
        }[self.source_type]
        valid_statuses, expected_strength = expected
        status_matches = (
            self.source_status in valid_statuses
            if isinstance(valid_statuses, set)
            else self.source_status == valid_statuses
        )
        if not status_matches or self.evidence_strength != expected_strength:
            raise ValueError("Evidence source status or strength does not match its provenance")
        if self.relationship_to_subject != "OTHER_PROPERTY":
            raise ValueError("Comparable evidence must refer to another property")
        return self


class PricingSourceCounts(StrictModel):
    listing_asking_rent: int = Field(ge=0, alias="listingAskingRent")
    rental_offer: int = Field(ge=0, alias="rentalOffer")
    lease_agreed_rent: int = Field(ge=0, alias="leaseAgreedRent")


class PricingDeterministicAssessment(StrictModel):
    evidence_sufficiency: PricingEvidenceSufficiency = Field(
        strict=False,
        alias="evidenceSufficiency",
    )
    confidence: PricingConfidence = Field(strict=False)
    usable_evidence_count: int = Field(ge=0, alias="usableEvidenceCount")
    source_counts: PricingSourceCounts = Field(alias="sourceCounts")

    @model_validator(mode="after")
    def validate_supplied_counts(self) -> "PricingDeterministicAssessment":
        counts = self.source_counts
        if self.usable_evidence_count != (
            counts.listing_asking_rent + counts.rental_offer + counts.lease_agreed_rent
        ):
            raise ValueError("usableEvidenceCount must equal the sum of source counts")
        return self


class PricingAnalysisAgentRequest(StrictModel):
    workflow_id: UUID = Field(
        validation_alias=AliasChoices("workflowId", "workflow_id"),
        serialization_alias="workflowId",
    )
    property_id: UUID = Field(
        validation_alias=AliasChoices("propertyId", "property_id"),
        serialization_alias="propertyId",
    )
    objective: str = Field(min_length=1, max_length=200)
    property_facts: PricingPropertyFacts = Field(
        validation_alias=AliasChoices("propertyFacts", "property_facts"),
        serialization_alias="propertyFacts",
    )
    comparables: list[PricingComparableEvidence] = Field(max_length=100)
    deterministic_assessment: PricingDeterministicAssessment = Field(
        validation_alias=AliasChoices("deterministicAssessment", "deterministic_assessment"),
        serialization_alias="deterministicAssessment",
    )
    evidence_policy_version: str = Field(
        min_length=1,
        max_length=50,
        validation_alias=AliasChoices("evidencePolicyVersion", "evidence_policy_version"),
        serialization_alias="evidencePolicyVersion",
    )

    @field_validator("workflow_id", "property_id", mode="before")
    @classmethod
    def parse_uuid(cls, value: Any) -> UUID:
        if isinstance(value, UUID):
            return value
        if not isinstance(value, str):
            raise ValueError("Identifier must be a UUID string")
        try:
            return UUID(value)
        except (ValueError, AttributeError) as exception:
            raise ValueError("Identifier must be a UUID string") from exception

    @model_validator(mode="after")
    def validate_request_consistency(self) -> "PricingAnalysisAgentRequest":
        if self.objective != "Analyze an evidence-supported monthly rental range.":
            raise ValueError("Unsupported pricing objective")
        if self.evidence_policy_version != "pricing-v1":
            raise ValueError("Unsupported evidence policy version")
        if len({item.evidence_ref for item in self.comparables}) != len(self.comparables):
            raise ValueError("Comparable evidence references must be unique")
        if self.property_facts.city.casefold().strip() == "":
            raise ValueError("Property city is required")
        if self.deterministic_assessment.usable_evidence_count != len(self.comparables):
            raise ValueError("Assessment evidence count does not match supplied comparables")
        if (
            self.deterministic_assessment.evidence_sufficiency
            == PricingEvidenceSufficiency.INSUFFICIENT
        ) != (len(self.comparables) == 0):
            raise ValueError("INSUFFICIENT assessment must correspond to zero supplied comparables")
        return self


class PricingModelAnalysisDraft(StrictModel):
    recommended_min_rent: Decimal | None = Field(
        default=None,
        max_digits=18,
        decimal_places=2,
        alias="recommendedMinRent",
    )
    recommended_max_rent: Decimal | None = Field(
        default=None,
        max_digits=18,
        decimal_places=2,
        alias="recommendedMaxRent",
    )
    central_recommended_rent: Decimal | None = Field(
        default=None,
        max_digits=18,
        decimal_places=2,
        alias="centralRecommendedRent",
    )
    cited_evidence_refs: list[str] = Field(default_factory=list, max_length=100, alias="citedEvidenceRefs")
    rationale: str = Field(min_length=1, max_length=2000)
    limitations: list[str] = Field(default_factory=list, max_length=50)
    warnings: list[str] = Field(default_factory=list, max_length=50)

    @field_validator(
        "recommended_min_rent",
        "recommended_max_rent",
        "central_recommended_rent",
        mode="before",
    )
    @classmethod
    def parse_recommendation_decimal(cls, value: Any) -> Decimal | None:
        if value is None:
            return None
        return _parse_json_decimal(value, allow_zero=False)

    @field_serializer(
        "recommended_min_rent",
        "recommended_max_rent",
        "central_recommended_rent",
        when_used="json",
    )
    def serialize_recommendation_decimal(self, value: Decimal | None) -> int | float | None:
        return None if value is None else _serialize_json_decimal(value)

    @field_validator("rationale")
    @classmethod
    def rationale_must_not_claim_currency_or_mutation(cls, value: str) -> str:
        _reject_currency_or_mutation_claim(value)
        return value

    @field_validator("limitations", "warnings")
    @classmethod
    def text_lists_must_not_claim_currency_or_mutation(
        cls,
        values: list[str],
    ) -> list[str]:
        for value in values:
            _reject_currency_or_mutation_claim(value)
        return values

    @model_validator(mode="after")
    def validate_recommendation_group(self) -> "PricingModelAnalysisDraft":
        has_min = self.recommended_min_rent is not None
        has_max = self.recommended_max_rent is not None
        if has_min != has_max:
            raise ValueError("Minimum and maximum rent must be supplied together")
        if len(set(self.cited_evidence_refs)) != len(self.cited_evidence_refs):
            raise ValueError("Cited evidence references must be unique")
        return self


class PricingExecutionMetadata(StrictModel):
    workflow_plan_version: str = Field(alias="workflowPlanVersion")
    expected_steps: list[str] = Field(min_length=6, max_length=6, alias="expectedSteps")
    executed_steps: list[str] = Field(min_length=5, max_length=6, alias="executedSteps")
    skipped_steps: list[str] = Field(max_length=1, alias="skippedSteps")


class PricingAnalysisAgentResponse(StrictModel):
    workflow_id: UUID = Field(alias="workflowId")
    property_id: UUID = Field(alias="propertyId")
    model_draft: PricingModelAnalysisDraft = Field(alias="modelDraft")
    execution_metadata: PricingExecutionMetadata = Field(alias="executionMetadata")
    agent_version: str = Field(min_length=1, max_length=100, alias="agentVersion")

    @field_validator("workflow_id", "property_id", mode="before")
    @classmethod
    def parse_response_uuid(cls, value: Any) -> UUID:
        if isinstance(value, UUID):
            return value
        if not isinstance(value, str):
            raise ValueError("Identifier must be a UUID string")
        try:
            return UUID(value)
        except (ValueError, AttributeError) as exception:
            raise ValueError("Identifier must be a UUID string") from exception


def _parse_json_decimal(value: Any, *, allow_zero: bool) -> Decimal:
    if isinstance(value, bool) or not isinstance(value, (int, float, Decimal)):
        raise ValueError("Rent must be a JSON number")
    try:
        parsed = value if isinstance(value, Decimal) else Decimal(str(value))
    except (InvalidOperation, ValueError) as exception:
        raise ValueError("Rent must be a finite decimal number") from exception
    if not parsed.is_finite() or parsed < 0 or (not allow_zero and parsed == 0):
        raise ValueError("Rent must be a positive finite decimal number")
    return parsed


def _serialize_json_decimal(value: Decimal) -> int | float:
    if value == value.to_integral_value():
        return int(value)
    return float(value)


def _parse_datetime(value: Any) -> datetime:
    if isinstance(value, datetime):
        parsed = value
    elif isinstance(value, str):
        try:
            parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError as exception:
            raise ValueError("Timestamp must be an ISO 8601 datetime") from exception
    else:
        raise ValueError("Timestamp must be an ISO 8601 datetime")
    if parsed.tzinfo is None or parsed.utcoffset() is None:
        raise ValueError("Timestamp must include a timezone")
    return parsed


_CURRENCY_PATTERN = re.compile(
    r"(?i)(?:\b(?:USD|LKR|INR|EUR|GBP|Rs\.?|rupees?|dollars?)\b|[$€£₹])"
)
_MUTATION_PATTERN = re.compile(r"(?i)\b(?:apply|update|change|set|modify)\b.{0,50}\brent\b")


def _reject_currency_or_mutation_claim(value: str) -> None:
    if _CURRENCY_PATTERN.search(value):
        raise ValueError("Pricing analysis must not claim a currency")
    if _MUTATION_PATTERN.search(value):
        raise ValueError("Pricing analysis must not recommend an automatic rent mutation")
