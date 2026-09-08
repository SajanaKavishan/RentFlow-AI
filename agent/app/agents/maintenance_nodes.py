"""Structured LangGraph nodes for advisory maintenance coordination."""

from __future__ import annotations

from typing import Any, Awaitable, Callable

from app.graph.maintenance_state import MaintenanceCoordinationAgentState
from app.schemas.maintenance import (
    MAINTENANCE_PLAN_STEPS,
    MaintenanceCoordinationRecommendation,
    MaintenanceCoordinationSummary,
    MaintenanceInformationReview,
    MaintenanceIssueAssessment,
    MaintenancePlan,
    MaintenanceUrgencyAssessment,
)
from app.services.model_provider import ModelProvider, request_structured_output

Node = Callable[[MaintenanceCoordinationAgentState], Awaitable[dict[str, Any]]]

_ADVISORY_SAFETY = (
    "This agent is advisory only. Never change request status, approve an estimate, "
    "assign a technician, or modify a database. Use only supplied structured data."
)


def create_maintenance_nodes(
    provider: ModelProvider,
    *,
    timeout_seconds: float,
    agent_version: str,
) -> dict[str, Node]:
    async def plan(state: MaintenanceCoordinationAgentState) -> dict[str, Any]:
        output = await request_structured_output(provider, output_schema=MaintenancePlan, instructions=f"Create this fixed maintenance coordination plan: {MAINTENANCE_PLAN_STEPS}. {_ADVISORY_SAFETY}", input_data={"maintenanceRequest": state["maintenance_request"]}, timeout_seconds=timeout_seconds, invocation_name="maintenance_planner")
        return {"plan": output.model_dump(mode="json"), "execution_steps": ["plan"]}

    async def classify_assess_issue(state: MaintenanceCoordinationAgentState) -> dict[str, Any]:
        output = await request_structured_output(provider, output_schema=MaintenanceIssueAssessment, instructions=f"Classify and assess the maintenance issue. {_ADVISORY_SAFETY}", input_data={"maintenanceRequest": state["maintenance_request"]}, timeout_seconds=timeout_seconds, invocation_name="maintenance_issue_assessment")
        return {"issue_assessment": output.model_dump(mode="json"), "execution_steps": [*state["execution_steps"], "classify_assess_issue"]}

    async def assess_urgency(state: MaintenanceCoordinationAgentState) -> dict[str, Any]:
        output = await request_structured_output(provider, output_schema=MaintenanceUrgencyAssessment, instructions=f"Assess urgency from the request and issue assessment. {_ADVISORY_SAFETY}", input_data={"maintenanceRequest": state["maintenance_request"], "issueAssessment": state["issue_assessment"]}, timeout_seconds=timeout_seconds, invocation_name="maintenance_urgency_assessment")
        return {"urgency_assessment": output.model_dump(mode="json"), "execution_steps": [*state["execution_steps"], "assess_urgency"]}

    async def review_maintenance_information(state: MaintenanceCoordinationAgentState) -> dict[str, Any]:
        output = await request_structured_output(provider, output_schema=MaintenanceInformationReview, instructions=f"Review available maintenance and estimate information; identify gaps. {_ADVISORY_SAFETY}", input_data={"maintenanceRequest": state["maintenance_request"], "urgencyAssessment": state["urgency_assessment"]}, timeout_seconds=timeout_seconds, invocation_name="maintenance_information_review")
        return {"information_review": output.model_dump(mode="json"), "execution_steps": [*state["execution_steps"], "review_maintenance_information"]}

    async def produce_coordination_recommendation(state: MaintenanceCoordinationAgentState) -> dict[str, Any]:
        output = await request_structured_output(provider, output_schema=MaintenanceCoordinationRecommendation, instructions=f"Produce an advisory coordination recommendation. {_ADVISORY_SAFETY}", input_data={"maintenanceRequest": state["maintenance_request"], "issueAssessment": state["issue_assessment"], "urgencyAssessment": state["urgency_assessment"], "informationReview": state["information_review"]}, timeout_seconds=timeout_seconds, invocation_name="maintenance_coordination_recommendation")
        return {"coordination_recommendation": output.model_dump(mode="json"), "execution_steps": [*state["execution_steps"], "produce_coordination_recommendation"]}

    async def summarize(state: MaintenanceCoordinationAgentState) -> dict[str, Any]:
        output = await request_structured_output(provider, output_schema=MaintenanceCoordinationSummary, instructions=f"Summarize the advisory recommendation. Set agentVersion to '{agent_version}'. {_ADVISORY_SAFETY}", input_data={"recommendation": state["coordination_recommendation"], "informationReview": state["information_review"]}, timeout_seconds=timeout_seconds, invocation_name="maintenance_summary")
        summary = output.model_copy(update={"agent_version": agent_version})
        return {"final_summary": summary.model_dump(mode="json", by_alias=True), "execution_steps": [*state["execution_steps"], "summarize"]}

    return {"plan": plan, "classify_assess_issue": classify_assess_issue, "assess_urgency": assess_urgency, "review_maintenance_information": review_maintenance_information, "produce_coordination_recommendation": produce_coordination_recommendation, "summarize": summarize}