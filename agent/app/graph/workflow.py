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
    supporting_document_verifier=None,
    cross_document_analyzer=None,
    vision_provider: ModelProvider | None = None,
    max_pdf_pages: int = 5,
    max_extracted_characters: int = 50_000,
    max_model_input_characters: int = 20_000,
    extraction_timeout_seconds: float = 20.0,
    income_tolerance_percent: float = 5.0,
):
    graph = StateGraph(ApplicationValidationAgentState)
    nodes = create_nodes(
        provider,
        timeout_seconds=timeout_seconds,
        agent_version=agent_version,
        supporting_document_verifier=supporting_document_verifier,
        cross_document_analyzer=cross_document_analyzer,
        vision_provider=vision_provider,
        max_pdf_pages=max_pdf_pages,
        max_extracted_characters=max_extracted_characters,
        max_model_input_characters=max_model_input_characters,
        extraction_timeout_seconds=extraction_timeout_seconds,
        income_tolerance_percent=income_tolerance_percent,
    )
    for name, node in nodes.items():
        graph.add_node(name, node)

    graph.add_edge(START, "plan")
    graph.add_edge("plan", "analyze_application_data")
    graph.add_edge("analyze_application_data", "analyze_document_metadata")
    graph.add_edge("analyze_document_metadata", "verify_supporting_documents")
    graph.add_edge("verify_supporting_documents", "analyze_cross_document_consistency")
    graph.add_edge("analyze_cross_document_consistency", "analyze_consistency")
    graph.add_edge("analyze_consistency", "summarize_findings")
    graph.add_edge("summarize_findings", END)
    return graph.compile()
