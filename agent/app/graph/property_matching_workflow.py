"""Construction of the property matching LangGraph."""

from langgraph.graph import END, START, StateGraph

from app.agents.property_matching_nodes import create_property_matching_nodes
from app.graph.property_matching_state import PropertyMatchingAgentState
from app.services.model_provider import ModelProvider


def build_property_matching_graph(
    provider: ModelProvider,
    *,
    timeout_seconds: float,
    agent_version: str,
):
    graph = StateGraph(PropertyMatchingAgentState)

    nodes = create_property_matching_nodes(
        provider,
        timeout_seconds=timeout_seconds,
        agent_version=agent_version,
    )

    for name, node in nodes.items():
        graph.add_node(name, node)

    graph.add_edge(START, "plan")
    graph.add_edge("plan", "analyze_matches")
    graph.add_edge("analyze_matches", "summarize")
    graph.add_edge("summarize", END)

    return graph.compile()