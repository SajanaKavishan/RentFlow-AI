"""Construction of the fixed rental price analysis LangGraph."""

from langgraph.graph import END, START, StateGraph

from app.agents.pricing_nodes import (
    PRICING_WORKFLOW_STEPS,
    create_pricing_nodes,
)
from app.graph.pricing_state import PricingAnalysisAgentState
from app.schemas.pricing import PricingAnalysisAgentRequest, PricingEvidenceSufficiency
from app.services.model_provider import ModelProvider


def build_pricing_analysis_graph(
    provider: ModelProvider,
    *,
    timeout_seconds: float,
    agent_version: str,
):
    graph = StateGraph(PricingAnalysisAgentState)
    nodes = create_pricing_nodes(
        provider,
        timeout_seconds=timeout_seconds,
        agent_version=agent_version,
    )
    for name, node in nodes.items():
        graph.add_node(name, node)

    graph.add_edge(START, "plan")
    graph.add_edge("plan", "collect_property_facts")
    graph.add_edge("collect_property_facts", "collect_rental_evidence")

    def next_after_evidence(state: PricingAnalysisAgentState) -> str:
        request = PricingAnalysisAgentRequest.model_validate(state["request"])
        return (
            "validate_pricing_recommendation"
            if request.deterministic_assessment.evidence_sufficiency
            == PricingEvidenceSufficiency.INSUFFICIENT
            else "analyse_pricing_evidence"
        )

    graph.add_conditional_edges(
        "collect_rental_evidence",
        next_after_evidence,
        {
            "analyse_pricing_evidence": "analyse_pricing_evidence",
            "validate_pricing_recommendation": "validate_pricing_recommendation",
        },
    )
    graph.add_edge("analyse_pricing_evidence", "validate_pricing_recommendation")
    graph.add_edge("validate_pricing_recommendation", "produce_pricing_result")
    graph.add_edge("produce_pricing_result", END)
    return graph.compile()


def initial_pricing_state(request: PricingAnalysisAgentRequest) -> PricingAnalysisAgentState:
    return {
        "request": request.model_dump(mode="json", by_alias=True),
        "plan": None,
        "property_facts": None,
        "comparables": None,
        "analysis_draft": None,
        "validated_draft": None,
        "validation_findings": [],
        "execution_steps": [],
        "skipped_steps": [],
        "response": None,
    }
