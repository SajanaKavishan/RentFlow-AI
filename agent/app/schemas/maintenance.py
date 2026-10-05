"""Closed maintenance contracts matching the authoritative ASP.NET domain."""

from __future__ import annotations

from decimal import Decimal
from enum import Enum
from typing import Annotated, Literal

from pydantic import Field, field_validator, model_validator
from app.schemas.common import StrictModel


class MaintenanceCategory(str, Enum):
    PLUMBING = "Plumbing"
    ELECTRICAL = "Electrical"
    APPLIANCE = "Appliance"
    STRUCTURAL = "Structural"
    SECURITY = "Security"
    PEST = "Pest"
    OTHER = "Other"
    HVAC = "Hvac"
    LOCKS_DOORS = "LocksDoors"


class MaintenancePriority(str, Enum):
    LOW = "Low"
    NORMAL = "Normal"
    HIGH = "High"
    EMERGENCY = "Emergency"


class MaintenanceStatus(str, Enum):
    SUBMITTED = "Submitted"
    TRIAGED = "Triaged"
    ASSIGNED = "Assigned"
    ESTIMATE_PENDING = "EstimatePending"
    ESTIMATE_SUBMITTED = "EstimateSubmitted"
    AWAITING_APPROVAL = "AwaitingLandlordApproval"
    APPROVED = "Approved"
    REJECTED = "Rejected"
    IN_PROGRESS = "InProgress"
    COMPLETED = "Completed"
    CANCELLED = "Cancelled"


Confidence = Literal["High", "Medium", "Low", "Unknown"]
MaintenanceNextAction = Literal[
    "triage", "assign-technician", "estimate-pending", "submit-estimate",
    "submit-for-review", "review-estimate", "start-work", "complete-work",
]
NEXT_ACTION_BY_STATUS = {
    MaintenanceStatus.SUBMITTED: "triage",
    MaintenanceStatus.TRIAGED: "assign-technician",
    MaintenanceStatus.ASSIGNED: "estimate-pending",
    MaintenanceStatus.ESTIMATE_PENDING: "submit-estimate",
    MaintenanceStatus.ESTIMATE_SUBMITTED: "submit-for-review",
    MaintenanceStatus.AWAITING_APPROVAL: "review-estimate",
    MaintenanceStatus.APPROVED: "start-work",
    MaintenanceStatus.IN_PROGRESS: "complete-work",
    MaintenanceStatus.REJECTED: None,
    MaintenanceStatus.COMPLETED: None,
    MaintenanceStatus.CANCELLED: None,
}
FlagCode = Literal[
    "InsufficientInformation", "CategoryDescriptionMismatch", "EstimateExplanationMissing",
    "EstimateScopeMismatch", "PhotoUnavailable", "PhotoUnreadable", "UrgencyNeedsHumanReview",
]
BoundedMessage = Annotated[str, Field(min_length=1, max_length=1000)]
Cost = Annotated[Decimal, Field(strict=False, ge=0, allow_inf_nan=False)]


class RepairEstimate(StrictModel):
    version_number: int = Field(ge=1, alias="versionNumber")
    labor_cost: Cost = Field(alias="laborCost")
    parts_cost: Cost = Field(alias="partsCost")
    additional_cost: Cost = Field(alias="additionalCost")
    total_cost: Cost = Field(alias="totalCost")
    notes: str | None = Field(max_length=4000)
    status: Literal["Draft", "Submitted", "RevisionRequested", "Approved", "Rejected", "Superseded"]


class MaintenanceAttachmentMetadata(StrictModel):
    attachment_id: str = Field(min_length=1, max_length=200, alias="attachmentId")
    content_type: Literal["image/jpeg", "image/png", "image/webp"] = Field(alias="contentType")
    file_size: int = Field(ge=1, le=10 * 1024 * 1024, alias="fileSize")


class MaintenanceEvidencePhoto(StrictModel):
    attachment_id: str = Field(min_length=1, max_length=200, alias="attachmentId")
    content_type: Literal["image/jpeg", "image/png", "image/webp"] = Field(alias="contentType")
    media_base64: str = Field(min_length=1, max_length=699052, alias="mediaBase64")


class MaintenanceCoordinationRequest(StrictModel):
    maintenance_request_id: str = Field(min_length=1, max_length=200, alias="maintenanceRequestId")
    title: str = Field(min_length=1, max_length=200)
    description: str = Field(min_length=1, max_length=4000)
    category: MaintenanceCategory = Field(strict=False)
    priority: MaintenancePriority = Field(strict=False)
    current_status: MaintenanceStatus = Field(strict=False, alias="currentStatus")
    preferred_access_window: Literal["Morning", "Afternoon", "Evening"] | None = Field(alias="preferredAccessWindow")
    has_assigned_technician: bool = Field(alias="hasAssignedTechnician")
    repair_estimate: RepairEstimate | None = Field(default=None, alias="repairEstimate")
    attachments: list[MaintenanceAttachmentMetadata] = Field(default_factory=list, max_length=5)
    evidence_photos: list[MaintenanceEvidencePhoto] = Field(default_factory=list, max_length=5, alias="evidencePhotos")
    photo_limitations: list[Literal["PhotoUnavailable", "PhotoUnreadable"]] = Field(default_factory=list, max_length=2, alias="photoLimitations")

    @model_validator(mode="after")
    def bounded_correlated_media(self):
        ids = [item.attachment_id for item in self.attachments]
        media_ids = [item.attachment_id for item in self.evidence_photos]
        if len(ids) != len(set(ids)) or len(media_ids) != len(set(media_ids)) or not set(media_ids).issubset(ids):
            raise ValueError("Photos must correlate to unique request attachments")
        if sum(len(item.media_base64) for item in self.evidence_photos) > 2796208:
            raise ValueError("Aggregate media payload exceeds its limit")
        return self


MAINTENANCE_PLAN_STEPS = (
    "classify_assess_issue", "assess_urgency", "review_maintenance_information",
    "produce_coordination_recommendation", "summarize",
)


class MaintenancePlan(StrictModel):
    steps: list[str] = Field(min_length=5, max_length=5)

    @model_validator(mode="after")
    def require_fixed_order(self) -> "MaintenancePlan":
        if tuple(self.steps) != MAINTENANCE_PLAN_STEPS:
            raise ValueError("Maintenance plan must contain every allowed step exactly once in fixed order")
        return self


class MaintenanceIssueAssessment(StrictModel):
    suggested_category: MaintenanceCategory | None = Field(strict=False, alias="suggestedCategory")
    category_confidence: Confidence = Field(alias="categoryConfidence")
    findings: list[BoundedMessage] = Field(default_factory=list, max_length=50)
    explanation: str = Field(min_length=1, max_length=2000)


class MaintenanceUrgencyAssessment(StrictModel):
    suggested_priority: MaintenancePriority | None = Field(strict=False, alias="suggestedPriority")
    priority_confidence: Confidence = Field(alias="priorityConfidence")
    urgency_reason: str = Field(min_length=1, max_length=2000)
    warnings: list[BoundedMessage] = Field(default_factory=list, max_length=50)


class MaintenanceInformationReview(StrictModel):
    available_information: list[BoundedMessage] = Field(default_factory=list, max_length=50)
    missing_information: list[BoundedMessage] = Field(default_factory=list, max_length=50)
    warnings: list[BoundedMessage] = Field(default_factory=list, max_length=50)


class MaintenanceValidationFlag(StrictModel):
    code: FlagCode
    message: BoundedMessage


class MaintenanceCoordinationRecommendation(StrictModel):
    suggested_category: MaintenanceCategory | None = Field(strict=False, alias="suggestedCategory")
    category_confidence: Confidence = Field(alias="categoryConfidence")
    suggested_priority: MaintenancePriority | None = Field(strict=False, alias="suggestedPriority")
    priority_confidence: Confidence = Field(alias="priorityConfidence")
    recommended_technician_category: MaintenanceCategory | None = Field(strict=False, alias="recommendedTechnicianCategory")
    next_action: MaintenanceNextAction | None = Field(alias="nextAction")
    validation_flags: list[MaintenanceValidationFlag] = Field(max_length=50, alias="validationFlags")
    rationale: str = Field(min_length=1, max_length=3000)
    requires_human_review: Literal[True] = Field(alias="requiresHumanReview")

    @field_validator("requires_human_review", mode="before")
    @classmethod
    def literal_human_review(cls, value):
        if value is not True:
            raise ValueError("Human review must be explicitly true")
        return value

    @model_validator(mode="after")
    def require_uncertainty_for_missing_suggestions(self):
        for suggestion, confidence in (
            (self.suggested_category, self.category_confidence),
            (self.suggested_priority, self.priority_confidence),
        ):
            if suggestion is None and confidence not in {"Low", "Unknown"}:
                raise ValueError("Missing suggestions must have Low or Unknown confidence")
        return self


class MaintenanceCoordinationSummary(MaintenanceCoordinationRecommendation):
    agent_version: str = Field(min_length=1, max_length=100, alias="agentVersion")


class MaintenanceVisualObservation(StrictModel):
    photo_index: int = Field(ge=0, le=4, alias="photoIndex")
    relevance: Literal["Relevant", "Irrelevant", "Unreadable"]
    observations: list[Annotated[str, Field(min_length=1, max_length=300)]] = Field(max_length=4)
    suggested_category: MaintenanceCategory | None = Field(strict=False, alias="suggestedCategory")
    category_confidence: Confidence = Field(alias="categoryConfidence")
    safety_concern: bool = Field(alias="safetyConcern")
    text_photo_conflict: bool = Field(alias="textPhotoConflict")

    @model_validator(mode="after")
    def require_visible_evidence(self):
        if (self.relevance != "Relevant" and self.suggested_category is not None
                or self.suggested_category is None and self.category_confidence not in {"Low", "Unknown"}
                or self.relevance == "Relevant" and not self.observations):
            raise ValueError("Visual suggestions require visible relevant evidence")
        return self


class MaintenanceVisualEvidence(StrictModel):
    photos: list[MaintenanceVisualObservation] = Field(min_length=1, max_length=5)
    requires_human_review: Literal[True] = Field(alias="requiresHumanReview")

    @field_validator("requires_human_review", mode="before")
    @classmethod
    def literal_review(cls, value):
        if value is not True:
            raise ValueError("Human review must be explicitly true")
        return value


class MaintenancePhotoEvidenceSummary(StrictModel):
    supplied_photo_count: int = Field(ge=0, le=5, alias="suppliedPhotoCount")
    analyzed_photo_count: int = Field(ge=0, le=5, alias="analyzedPhotoCount")

    @model_validator(mode="after")
    def truthful_counts(self):
        if self.analyzed_photo_count > self.supplied_photo_count:
            raise ValueError("Analyzed count cannot exceed supplied count")
        return self


def validate_next_action(status: MaintenanceStatus, action: MaintenanceNextAction | None) -> None:
    # Null is a valid abstention; closed states always require it.
    if action is not None and action != NEXT_ACTION_BY_STATUS[status]:
        raise ValueError("Next action is not permitted for the current maintenance status")


class MaintenanceExecutionMetadata(StrictModel):
    executed_steps: list[str] = Field(min_length=6, max_length=6, alias="executedSteps")
    photo_evidence: MaintenancePhotoEvidenceSummary | None = Field(default=None, alias="photoEvidence")


class MaintenanceCoordinationResponse(StrictModel):
    maintenance_request_id: str = Field(alias="maintenanceRequestId")
    result: MaintenanceCoordinationSummary
    execution_metadata: MaintenanceExecutionMetadata = Field(alias="executionMetadata")
