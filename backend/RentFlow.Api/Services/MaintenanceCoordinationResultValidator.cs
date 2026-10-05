using RentFlow.Api.DTOs.Maintenance;
using RentFlow.Api.Models;

namespace RentFlow.Api.Services;

/// <summary>Validates recommendations independently of Python and provider formatting.</summary>
public static class MaintenanceCoordinationResultValidator
{
    private static readonly HashSet<string> Categories = Enum.GetNames<MaintenanceCategory>().ToHashSet(StringComparer.Ordinal);
    private static readonly HashSet<string> Priorities = Enum.GetNames<MaintenancePriority>().ToHashSet(StringComparer.Ordinal);
    private static readonly HashSet<string> Statuses = Enum.GetNames<MaintenanceRequestStatus>().ToHashSet(StringComparer.Ordinal);
    private static readonly HashSet<string> Confidence = new(["High", "Medium", "Low", "Unknown"], StringComparer.Ordinal);
    private static readonly HashSet<string> Flags = new([
        "InsufficientInformation", "CategoryDescriptionMismatch", "EstimateExplanationMissing",
        "EstimateScopeMismatch", "PhotoUnavailable", "PhotoUnreadable", "UrgencyNeedsHumanReview"], StringComparer.Ordinal);
    private static readonly string[] Steps =
        ["plan", "classify_assess_issue", "assess_urgency", "review_maintenance_information", "produce_coordination_recommendation", "summarize"];

    public static string? NextAction(string status) => status switch
    {
        nameof(MaintenanceRequestStatus.Submitted) => "triage",
        nameof(MaintenanceRequestStatus.Triaged) => "assign-technician",
        nameof(MaintenanceRequestStatus.Assigned) => "estimate-pending",
        nameof(MaintenanceRequestStatus.EstimatePending) => "submit-estimate",
        nameof(MaintenanceRequestStatus.EstimateSubmitted) => "submit-for-review",
        nameof(MaintenanceRequestStatus.AwaitingLandlordApproval) => "review-estimate",
        nameof(MaintenanceRequestStatus.Approved) => "start-work",
        nameof(MaintenanceRequestStatus.InProgress) => "complete-work",
        _ => null
    };

    public static void Validate(MaintenanceCoordinationAgentRequest request, MaintenanceCoordinationAgentResponse? response)
    {
        var result = response?.Result;
        if (response is null || response.MaintenanceRequestId != request.MaintenanceRequestId || result is null
            || !Statuses.Contains(request.CurrentStatus)
            || !OptionalMember(result.SuggestedCategory, Categories)
            || !OptionalMember(result.SuggestedPriority, Priorities)
            || !OptionalMember(result.RecommendedTechnicianCategory, Categories)
            || !Confidence.Contains(result.CategoryConfidence) || !Confidence.Contains(result.PriorityConfidence)
            || (result.SuggestedCategory is null && result.CategoryConfidence is not ("Low" or "Unknown"))
            || (result.SuggestedPriority is null && result.PriorityConfidence is not ("Low" or "Unknown"))
            || (result.NextAction is not null && result.NextAction != NextAction(request.CurrentStatus))
            || !result.RequiresHumanReview || !Bounded(result.Rationale, 3000) || !Bounded(result.AgentVersion, 100)
            || result.ValidationFlags is null || result.ValidationFlags.Count > 50
            || result.ValidationFlags.Any(flag => flag is null || !Flags.Contains(flag.Code) || !Bounded(flag.Message, 1000))
            || ((request.Priority == nameof(MaintenancePriority.Emergency) || result.SuggestedPriority == nameof(MaintenancePriority.Emergency))
                && !result.ValidationFlags.Any(flag => flag.Code == "UrgencyNeedsHumanReview"))
            || response.ExecutionMetadata?.ExecutedSteps is null
            || !response.ExecutionMetadata.ExecutedSteps.SequenceEqual(Steps))
        {
            throw new MaintenanceCoordinationAgentClientException(
                MaintenanceCoordinationAgentClientError.MalformedResponse,
                "The maintenance coordination agent returned an invalid structured response.");
        }
    }

    private static bool OptionalMember(string? value, HashSet<string> allowed) => value is null || allowed.Contains(value);
    private static bool Bounded(string? value, int maximum) => !string.IsNullOrWhiteSpace(value) && value.Length <= maximum;
}
