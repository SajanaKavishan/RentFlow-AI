"""Construction of the fixed application-validation LangGraph."""

from __future__ import annotations

from langgraph.graph import END, START, StateGraph

from app.agents.nodes import create_nodes
from app.graph.state import ApplicationValidationAgentState
from app.services.model_provider import ModelProvider


def build_application_validation_graph(
    provider: ModelProvider,
    *,
    timeout_seconds: float,
    agent_version: str,
):
    graph = StateGraph(ApplicationValidationAgentState)
    nodes = create_nodes(
        provider,
        timeout_seconds=timeout_seconds,
        agent_version=agent_version,
    )
    for name, node in nodes.items():
        graph.add_node(name, node)

    graph.add_edge(START, "plan")
    graph.add_edge("plan", "analyze_application_data")
    graph.add_edge("analyze_application_data", "analyze_document_metadata")
    graph.add_edge("analyze_document_metadata", "analyze_consistency")
    graph.add_edge("analyze_consistency", "summarize_findings")
    graph.add_edge("summarize_findings", END)
    return graph.compile()
