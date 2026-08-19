"""Distinct, structured LangGraph nodes for application validation analysis."""

from __future__ import annotations

import logging
from functools import wraps
from typing import Any, Awaitable, Callable

from pydantic import ValidationError

from app.graph.state import ApplicationValidationAgentState
from app.schemas.analysis import (
    ApplicationDataAnalysis,
    ConsistencyAnalysis,
    DocumentAnalysis,
    FinalAgentSummary,
)
from app.schemas.plan import Plan
from app.schemas.supporting_documents import (
    CrossDocumentConsistencyResult,
    SupportingDocumentInput,
    SupportingDocumentVerificationResult,
)
from app.services.diagnostics import (
    exception_type_name,
    log_development_event,
    safe_model_name,
    sanitized_exception_message,
)
from app.services.exceptions import AgentServiceError
from app.services.model_provider import ModelProvider, request_structured_output
from app.services.supporting_document_verification import (
    CrossDocumentConsistencyAnalyzer,
    PhaseAFakeCrossDocumentConsistencyAnalyzer,
    PhaseAFakeSupportingDocumentVerifier,
    SupportingDocumentVerifier,
)

Node = Callable[[ApplicationValidationAgentState], Awaitable[dict[str, Any]]]
logger = logging.getLogger(__name__)

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
    supporting_document_verifier: SupportingDocumentVerifier | None = None,
    cross_document_analyzer: CrossDocumentConsistencyAnalyzer | None = None,
) -> dict[str, Node]:
    document_verifier = supporting_document_verifier or PhaseAFakeSupportingDocumentVerifier()
    document_consistency_analyzer = (
        cross_document_analyzer or PhaseAFakeCrossDocumentConsistencyAnalyzer()
    )
    async def plan_analysis(state: ApplicationValidationAgentState) -> dict[str, Any]:
        output = await request_structured_output(
            provider,
            output_schema=Plan,
            instructions=(
                "Create the fixed application-validation plan. The only valid ordered "
                "steps are analyze_application_data, analyze_document_metadata, "
                "verify_supporting_documents, analyze_cross_document_consistency, "
                "analyze_consistency, summarize_findings. " + _SHARED_SAFETY
            ),
            input_data={"objective": state["objective"]},
            timeout_seconds=timeout_seconds,
            invocation_name="planner",
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
            invocation_name="application_data_analysis",
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
            invocation_name="document_analysis",
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
            invocation_name="consistency_analysis",
        )
        return {
            "consistency_analysis": output.model_dump(mode="json"),
            "execution_steps": [*state["execution_steps"], "analyze_consistency"],
        }

    async def verify_supporting_documents(
        state: ApplicationValidationAgentState,
    ) -> dict[str, Any]:
        inputs = [
            SupportingDocumentInput.model_validate(item)
            for item in state["supporting_document_inputs"]
        ]
        results = await document_verifier.verify(inputs)
        validated = [
            SupportingDocumentVerificationResult.model_validate(item)
            for item in results
        ]
        return {
            "supporting_document_verification": [
                item.model_dump(mode="json") for item in validated
            ],
            "execution_steps": [*state["execution_steps"], "verify_supporting_documents"],
        }

    async def analyze_cross_document_consistency(
        state: ApplicationValidationAgentState,
    ) -> dict[str, Any]:
        verification = [
            SupportingDocumentVerificationResult.model_validate(item)
            for item in state["supporting_document_verification"]
        ]
        result = await document_consistency_analyzer.analyze(
            state["application_data"], verification
        )
        validated = CrossDocumentConsistencyResult.model_validate(result)
        return {
            "cross_document_consistency": validated.model_dump(mode="json"),
            "execution_steps": [
                *state["execution_steps"],
                "analyze_cross_document_consistency",
            ],
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
            invocation_name="final_summary",
        )
        # The service owns version metadata, not the model.
        validated_summary = output.model_copy(
            update={
                "agent_version": agent_version,
                "supporting_document_verification": [
                    SupportingDocumentVerificationResult.model_validate(item)
                    for item in state["supporting_document_verification"]
                ],
                "cross_document_consistency": CrossDocumentConsistencyResult.model_validate(
                    state["cross_document_consistency"]
                ),
            }
        )
        return {
            "final_summary": validated_summary.model_dump(mode="json", by_alias=True),
            "execution_steps": [*state["execution_steps"], "summarize_findings"],
        }

    model_name = safe_model_name(provider.model_name)
    return {
        "plan": _with_node_diagnostics("planner", model_name, plan_analysis),
        "analyze_application_data": _with_node_diagnostics(
            "application_data_analysis", model_name, analyze_application_data
        ),
        "analyze_document_metadata": _with_node_diagnostics(
            "document_analysis", model_name, analyze_document_metadata
        ),
        "verify_supporting_documents": _with_node_diagnostics(
            "supporting_document_verification", model_name, verify_supporting_documents
        ),
        "analyze_cross_document_consistency": _with_node_diagnostics(
            "cross_document_consistency", model_name, analyze_cross_document_consistency
        ),
        "analyze_consistency": _with_node_diagnostics(
            "consistency_analysis", model_name, analyze_consistency
        ),
        "summarize_findings": _with_node_diagnostics(
            "final_summary", model_name, summarize_findings
        ),
    }


def _with_node_diagnostics(node_name: str, model_name: str, node: Node) -> Node:
    @wraps(node)
    async def instrumented(
        state: ApplicationValidationAgentState,
    ) -> dict[str, Any]:
        try:
            return await node(state)
        except AgentServiceError:
            # Model boundary failures already contain the provider/validation category.
            raise
        except Exception as exc:
            root_type = exception_type_name(exc)
            category = (
                "langgraph_state_schema_failure"
                if isinstance(exc, (KeyError, TypeError, ValidationError))
                or root_type.startswith("langgraph.")
                else "application_level_exception"
            )
            log_development_event(
                logger,
                "langgraph_node_failed",
                node=node_name,
                category=category,
                exception_type=root_type,
                status="none",
                model=model_name,
                message=sanitized_exception_message(exc),
            )
            raise

    return instrumented
