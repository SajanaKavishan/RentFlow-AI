using RentFlow.Api.DTOs.Maintenance;
using RentFlow.Api.Services;

namespace RentFlow.Api.Tests.Services;

internal static class MaintenanceCoordinationTestData
{
    public static MaintenanceCoordinationResult Result(MaintenanceCoordinationAgentRequest request) => new()
    {
        SuggestedCategory = request.Category,
        CategoryConfidence = "High",
        SuggestedPriority = request.Priority,
        PriorityConfidence = "Medium",
        RecommendedTechnicianCategory = request.Category,
        NextAction = MaintenanceCoordinationResultValidator.NextAction(request.CurrentStatus),
        ValidationFlags = request.Priority == "Emergency"
            ? [new() { Code = "UrgencyNeedsHumanReview", Message = "Review emergency handling." }] : [],
        Rationale = "Review the supplied maintenance evidence.",
        RequiresHumanReview = true,
        AgentVersion = "test-agent-1.0"
    };

    public static MaintenanceCoordinationExecutionMetadata Metadata() => new()
    {
        ExecutedSteps = ["plan", "classify_assess_issue", "assess_urgency", "review_maintenance_information", "produce_coordination_recommendation", "summarize"]
    };

    public static MaintenanceCoordinationAgentResponse Response(MaintenanceCoordinationAgentRequest request) => new()
    {
        MaintenanceRequestId = request.MaintenanceRequestId, Result = Result(request), ExecutionMetadata = Metadata()
    };
}
