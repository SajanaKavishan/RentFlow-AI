"""Construction of the fixed maintenance coordination LangGraph."""

from langgraph.graph import END, START, StateGraph

from app.agents.maintenance_nodes import create_maintenance_nodes
from app.graph.maintenance_state import MaintenanceCoordinationAgentState
from app.services.model_provider import ModelProvider


def build_maintenance_coordination_graph(
    provider: ModelProvider,
    *,
    timeout_seconds: float,
    agent_version: str,
):
    graph = StateGraph(MaintenanceCoordinationAgentState)
    nodes = create_maintenance_nodes(provider, timeout_seconds=timeout_seconds, agent_version=agent_version)
    for name, node in nodes.items():
        graph.add_node(name, node)
    graph.add_edge(START, "plan")
    graph.add_edge("plan", "classify_assess_issue")
    graph.add_edge("classify_assess_issue", "assess_urgency")
    graph.add_edge("assess_urgency", "review_maintenance_information")
    graph.add_edge("review_maintenance_information", "produce_coordination_recommendation")
    graph.add_edge("produce_coordination_recommendation", "summarize")
    graph.add_edge("summarize", END)
    return graph.compile()