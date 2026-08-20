"""HTTP response schemas."""

from __future__ import annotations

from pydantic import Field

from app.schemas.analysis import FinalAgentSummary
from app.schemas.common import StrictModel


class ExecutionMetadata(StrictModel):
    executed_steps: list[str] = Field(serialization_alias="executedSteps")


class AnalysisResponse(StrictModel):
    workflow_id: str = Field(serialization_alias="workflowId")
    application_id: str = Field(serialization_alias="applicationId")
    result: FinalAgentSummary
    execution_metadata: ExecutionMetadata = Field(serialization_alias="executionMetadata")


class ErrorDetail(StrictModel):
    code: str
    message: str
    retryable: bool


class ErrorResponse(StrictModel):
    error: ErrorDetail
