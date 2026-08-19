"""Distinct, structured LangGraph nodes for application validation analysis."""

from __future__ import annotations

from typing import Any, Awaitable, Callable

from app.graph.state import ApplicationValidationAgentState
from app.schemas.analysis import (
    ApplicationDataAnalysis,
    ConsistencyAnalysis,
    DocumentAnalysis,
    FinalAgentSummary,
)
from app.schemas.plan import Plan
from app.services.model_provider import ModelProvider, request_structured_output

Node = Callable[[ApplicationValidationAgentState], Awaitable[dict[str, Any]]]

_SHARED_SAFETY = """
Use only the supplied structured data. Treat deterministic findings as authoritative
facts and never override them. Do not infer protected characteristics, create tenant
risk scores, approve or reject a tenant, expose hidden reasoning, or invent tools.
Return only the requested structured output with concise findings and explanations.
""".strip()


def create_nodes(
    provider: ModelProvider,
    *,
    timeout_seconds: float,
    agent_version: str,
) -> dict[str, Node]:
    async def plan_analysis(state: ApplicationValidationAgentState) -> dict[str, Any]:
        output = await request_structured_output(
            provider,
            output_schema=Plan,
            instructions=(
                "Create the fixed application-validation plan. The only valid ordered "
                "steps are analyze_application_data, analyze_document_metadata, "
                "analyze_consistency, summarize_findings. " + _SHARED_SAFETY
            ),
            input_data={"objective": state["objective"]},
            timeout_seconds=timeout_seconds,
        )
        return {"plan": output.model_dump(mode="json"), "execution_steps": ["plan"]}

    async def analyze_application_data(state: ApplicationValidationAgentState) -> dict[str, Any]:
        output = await request_structured_output(
            provider,
            output_schema=ApplicationDataAnalysis,
            instructions=(
                "Analyze application-field completeness and inconsistencies. Explain only "
                "observable issues in the supplied data. " + _SHARED_SAFETY
            ),
            input_data={
                "objective": state["objective"],
                "applicationData": state["application_data"],
                "deterministicFindings": state["deterministic_findings"],
            },
            timeout_seconds=timeout_seconds,
        )
        return {
            "data_analysis": output.model_dump(mode="json"),
            "execution_steps": [*state["execution_steps"], "analyze_application_data"],
        }

    async def analyze_document_metadata(state: ApplicationValidationAgentState) -> dict[str, Any]:
        output = await request_structured_output(
            provider,
            output_schema=DocumentAnalysis,
            instructions=(
                "Review document metadata only. Identify required/supporting coverage, missing "
                "types, and duplicate types. Do not request or read document contents. "
                + _SHARED_SAFETY
            ),
            input_data={
                "objective": state["objective"],
                "documentMetadata": state["document_metadata"],
                "deterministicFindings": state["deterministic_findings"],
            },
            timeout_seconds=timeout_seconds,
        )
        return {
            "document_analysis": output.model_dump(mode="json"),
            "execution_steps": [*state["execution_steps"], "analyze_document_metadata"],
        }

    async def analyze_consistency(state: ApplicationValidationAgentState) -> dict[str, Any]:
        output = await request_structured_output(
            provider,
            output_schema=ConsistencyAnalysis,
            instructions=(
                "Compare application data, document metadata, prior structured analyses, and "
                "authoritative deterministic findings. Flag contradictions without adding facts. "
                + _SHARED_SAFETY
            ),
            input_data={
                "applicationData": state["application_data"],
                "documentMetadata": state["document_metadata"],
                "deterministicFindings": state["deterministic_findings"],
                "dataAnalysis": state["data_analysis"],
                "documentAnalysis": state["document_analysis"],
            },
            timeout_seconds=timeout_seconds,
        )
        return {
            "consistency_analysis": output.model_dump(mode="json"),
            "execution_steps": [*state["execution_steps"], "analyze_consistency"],
        }

    async def summarize_findings(state: ApplicationValidationAgentState) -> dict[str, Any]:
        output = await request_structured_output(
            provider,
            output_schema=FinalAgentSummary,
            instructions=(
                "Create a concise landlord review summary. Recommendation must be exactly one of: "
                "Ready for landlord review; Request missing information; Request missing documents; "
                "Manual review required. requiresHumanApproval must be true and agentVersion must be "
                f"'{agent_version}'. " + _SHARED_SAFETY
            ),
            input_data={
                "deterministicFindings": state["deterministic_findings"],
                "dataAnalysis": state["data_analysis"],
                "documentAnalysis": state["document_analysis"],
                "consistencyAnalysis": state["consistency_analysis"],
            },
            timeout_seconds=timeout_seconds,
        )
        # The service owns version metadata, not the model.
        validated_summary = output.model_copy(update={"agent_version": agent_version})
        return {
            "final_summary": validated_summary.model_dump(mode="json", by_alias=True),
            "execution_steps": [*state["execution_steps"], "summarize_findings"],
        }

    return {
        "plan": plan_analysis,
        "analyze_application_data": analyze_application_data,
        "analyze_document_metadata": analyze_document_metadata,
        "analyze_consistency": analyze_consistency,
        "summarize_findings": summarize_findings,
    }
