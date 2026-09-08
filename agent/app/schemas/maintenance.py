"""Strict request and structured output models for maintenance coordination."""

from __future__ import annotations

from typing import Literal

from pydantic import AliasChoices, Field, field_validator, model_validator

from app.schemas.common import StrictModel, reject_sensitive_input_keys


MaintenancePriority = Literal["low", "medium", "high", "urgent"]
MaintenanceStatus = Literal["open", "in_progress", "on_hold", "completed", "cancelled"]


class RepairEstimate(StrictModel):
    amount: float = Field(ge=0, le=10_000_000)
    currency: str = Field(min_length=3, max_length=3)
    notes: str | None = Field(default=None, max_length=1000)


class MaintenanceAttachmentMetadata(StrictModel):
    attachment_id: str = Field(
        min_length=1,
        max_length=200,
        validation_alias=AliasChoices("attachmentId", "attachment_id"),
        serialization_alias="attachmentId",
    )
    file_name: str = Field(
        min_length=1,
        max_length=255,
        validation_alias=AliasChoices("fileName", "file_name"),
        serialization_alias="fileName",
    )
    content_type: str = Field(
        min_length=1,
        max_length=100,
        validation_alias=AliasChoices("contentType", "content_type"),
        serialization_alias="contentType",
    )


class MaintenanceCoordinationRequest(StrictModel):
    maintenance_request_id: str = Field(
        min_length=1,
        max_length=200,
        validation_alias=AliasChoices("maintenanceRequestId", "maintenance_request_id"),
        serialization_alias="maintenanceRequestId",
    )
    title: str = Field(min_length=1, max_length=300)
    description: str = Field(min_length=1, max_length=5000)
    category: str = Field(min_length=1, max_length=100)
    priority: MaintenancePriority
    current_status: MaintenanceStatus = Field(
        validation_alias=AliasChoices("currentStatus", "current_status"),
        serialization_alias="currentStatus",
    )
    assigned_technician_id: str | None = Field(
        default=None,
        max_length=200,
        validation_alias=AliasChoices("assignedTechnicianId", "assigned_technician_id"),
        serialization_alias="assignedTechnicianId",
    )
    repair_estimate: RepairEstimate | None = Field(
        default=None,
        validation_alias=AliasChoices("repairEstimate", "repair_estimate"),
        serialization_alias="repairEstimate",
    )
    attachments: list[MaintenanceAttachmentMetadata] = Field(
        default_factory=list,
        max_length=100,
    )

    @field_validator("description")
    @classmethod
    def description_must_be_safe_json_text(cls, value: str) -> str:
        reject_sensitive_input_keys({"description": value})
        return value


MaintenanceNextAction = Literal[
    "Request missing information",
    "Review repair estimate",
    "Schedule technician review",
    "Escalate for urgent human review",
    "Monitor existing maintenance assignment",
]


class MaintenancePlan(StrictModel):
    steps: list[str] = Field(min_length=5, max_length=5)

    @model_validator(mode="after")
    def require_fixed_order(self) -> "MaintenancePlan":
        if tuple(self.steps) != MAINTENANCE_PLAN_STEPS:
            raise ValueError("Maintenance plan must contain every allowed step exactly once in fixed order")
        return self


MAINTENANCE_PLAN_STEPS = (
    "classify_assess_issue",
    "assess_urgency",
    "review_maintenance_information",
    "produce_coordination_recommendation",
    "summarize",
)


class MaintenanceIssueAssessment(StrictModel):
    recommended_category: str = Field(min_length=1, max_length=100)
    findings: list[str] = Field(default_factory=list, max_length=50)
    explanation: str = Field(min_length=1, max_length=2000)


class MaintenanceUrgencyAssessment(StrictModel):
    recommended_priority: MaintenancePriority
    urgency_reason: str = Field(min_length=1, max_length=2000)
    warnings: list[str] = Field(default_factory=list, max_length=50)


class MaintenanceInformationReview(StrictModel):
    available_information: list[str] = Field(default_factory=list, max_length=100)
    missing_information: list[str] = Field(default_factory=list, max_length=100)
    warnings: list[str] = Field(default_factory=list, max_length=100)


class MaintenanceCoordinationRecommendation(StrictModel):
    recommended_category: str = Field(min_length=1, max_length=100)
    recommended_priority: MaintenancePriority
    next_action: MaintenanceNextAction
    reasoning: str = Field(min_length=1, max_length=3000)
    warnings: list[str] = Field(default_factory=list, max_length=100)


class MaintenanceCoordinationSummary(StrictModel):
    recommended_category: str = Field(
        min_length=1,
        max_length=100,
        alias="recommendedCategory",
    )
    recommended_priority: MaintenancePriority = Field(alias="recommendedPriority")
    next_action: MaintenanceNextAction = Field(alias="nextAction")
    reasoning: str = Field(min_length=1, max_length=3000)
    warnings: list[str] = Field(default_factory=list, max_length=100)
    agent_version: str = Field(min_length=1, max_length=100, alias="agentVersion")


class MaintenanceExecutionMetadata(StrictModel):
    executed_steps: list[str] = Field(
        min_length=6,
        max_length=6,
        alias="executedSteps",
    )


class MaintenanceCoordinationResponse(StrictModel):
    maintenance_request_id: str = Field(alias="maintenanceRequestId")
    result: MaintenanceCoordinationSummary
    execution_metadata: MaintenanceExecutionMetadata = Field(alias="executionMetadata")