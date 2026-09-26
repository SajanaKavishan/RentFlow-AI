"""Internal-only analysis API routes."""

from __future__ import annotations

from fastapi import APIRouter, Request

from app.graph.workflow import build_application_validation_graph
from app.graph.maintenance_workflow import build_maintenance_coordination_graph
from app.graph.pricing_workflow import build_pricing_analysis_graph, initial_pricing_state
from app.graph.property_matching_workflow import build_property_matching_graph
from app.schemas.property_matching import (
    PropertyMatchingRequest,
    PropertyMatchingResponse,
    PropertyMatchingSummary,
)
from app.schemas.analysis import FinalAgentSummary
from app.schemas.maintenance import (
    MaintenanceCoordinationRequest,
    MaintenanceCoordinationResponse,
    MaintenanceCoordinationSummary,
)
from app.schemas.requests import ApplicationValidationRequest
from app.schemas.pricing import PricingAnalysisAgentRequest, PricingAnalysisAgentResponse
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
        vision_provider=request.app.state.vision_model_provider,
        max_pdf_pages=settings.max_pdf_pages,
        max_extracted_characters=settings.max_extracted_characters,
        max_model_input_characters=settings.max_model_input_characters,
        extraction_timeout_seconds=settings.extraction_timeout_seconds,
        income_tolerance_percent=settings.income_tolerance_percent,
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
        "supporting_document_inputs": [
            item.model_dump(mode="json") for item in payload.supporting_documents
        ],
        "supporting_document_verification": [],
        "cross_document_consistency": None,
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


@router.post(
    "/internal/maintenance-coordination/analyze",
    response_model=MaintenanceCoordinationResponse,
    response_model_by_alias=True,
)
async def analyze_maintenance_coordination(
    payload: MaintenanceCoordinationRequest,
    request: Request,
) -> MaintenanceCoordinationResponse:
    settings = request.app.state.settings
    graph = build_maintenance_coordination_graph(
        request.app.state.model_provider,
        timeout_seconds=settings.ai_timeout_seconds,
        agent_version=settings.agent_version,
    )
    result = await graph.ainvoke(
        {
            "maintenance_request": payload.model_dump(mode="json", by_alias=True),
            "plan": None,
            "issue_assessment": None,
            "urgency_assessment": None,
            "information_review": None,
            "coordination_recommendation": None,
            "final_summary": None,
            "execution_steps": [],
        }
    )
    return MaintenanceCoordinationResponse(
        maintenance_request_id=payload.maintenance_request_id,
        result=MaintenanceCoordinationSummary.model_validate(result["final_summary"]),
        execution_metadata={"executedSteps": result["execution_steps"]},
    )
@router.post(
    "/internal/pricing-analysis/analyze",
    response_model=PricingAnalysisAgentResponse,
    response_model_by_alias=True,
)
async def analyze_pricing(
    payload: PricingAnalysisAgentRequest,
    request: Request,
) -> PricingAnalysisAgentResponse:
    settings = request.app.state.settings
    graph = build_pricing_analysis_graph(
        request.app.state.model_provider,
        timeout_seconds=settings.ai_timeout_seconds,
        agent_version=settings.agent_version,
    )
    result = await graph.ainvoke(initial_pricing_state(payload))
    return PricingAnalysisAgentResponse.model_validate(result["response"])


@router.post(
    "/internal/property-matching/analyze",
    response_model=PropertyMatchingResponse,
    response_model_by_alias=True,
)
async def analyze_property_matching(
    payload: PropertyMatchingRequest,
    request: Request,
) -> PropertyMatchingResponse:
    settings = request.app.state.settings

    graph = build_property_matching_graph(
        request.app.state.model_provider,
        timeout_seconds=settings.ai_timeout_seconds,
        agent_version=settings.agent_version,
    )

    result = await graph.ainvoke(
        {
            "preferences": payload.preferences.model_dump(
                mode="json",
                by_alias=True,
            ),
            "candidates": [
                candidate.model_dump(mode="json", by_alias=True)
                for candidate in payload.candidates
            ],
            "plan": None,
            "match_analysis": None,
            "final_summary": None,
            "execution_steps": [],
        }
    )

    return PropertyMatchingResponse(
        result=PropertyMatchingSummary.model_validate(
            result["final_summary"]
        ),
        execution_metadata={
            "executedSteps": result["execution_steps"]
        },
    )
