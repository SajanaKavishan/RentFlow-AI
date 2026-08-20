"""Internal-only application-validation API routes."""

from __future__ import annotations

from fastapi import APIRouter, Request

from app.graph.workflow import build_application_validation_graph
from app.schemas.analysis import FinalAgentSummary
from app.schemas.requests import ApplicationValidationRequest
from app.schemas.responses import AnalysisResponse, ExecutionMetadata

router = APIRouter()


@router.get("/health")
async def health() -> dict[str, str]:
    return {"status": "healthy"}


@router.post(
    "/internal/application-validation/analyze",
    response_model=AnalysisResponse,
    response_model_by_alias=True,
)
async def analyze_application_validation(
    payload: ApplicationValidationRequest,
    request: Request,
) -> AnalysisResponse:
    settings = request.app.state.settings
    graph = build_application_validation_graph(
        request.app.state.model_provider,
        timeout_seconds=settings.ai_timeout_seconds,
        agent_version=settings.agent_version,
    )
    state = {
        "workflow_id": payload.workflow_id,
        "application_id": payload.application_id,
        "objective": payload.objective,
        "application_data": payload.application_data,
        "document_metadata": [item.model_dump(mode="json") for item in payload.document_metadata],
        "deterministic_findings": [
            item.model_dump(mode="json") for item in payload.deterministic_findings
        ],
        "plan": None,
        "data_analysis": None,
        "document_analysis": None,
        "consistency_analysis": None,
        "final_summary": None,
        "errors": [],
        "execution_steps": [],
    }
    result = await graph.ainvoke(state)
    final_summary = FinalAgentSummary.model_validate(result["final_summary"])
    return AnalysisResponse(
        workflow_id=payload.workflow_id,
        application_id=payload.application_id,
        result=final_summary,
        execution_metadata=ExecutionMetadata(executed_steps=result["execution_steps"]),
    )
