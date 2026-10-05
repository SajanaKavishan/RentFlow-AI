using System.Text.Json.Serialization;

namespace RentFlow.Api.DTOs.Maintenance;

[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed class MaintenanceCoordinationAgentRequest
{
    public Guid MaintenanceRequestId { get; init; }
    public string Title { get; init; } = string.Empty;
    public string Description { get; init; } = string.Empty;
    public string Category { get; init; } = string.Empty;
    public string Priority { get; init; } = string.Empty;
    public string CurrentStatus { get; init; } = string.Empty;
    public string? PreferredAccessWindow { get; init; }
    public bool HasAssignedTechnician { get; init; }
    public MaintenanceCoordinationEstimate? RepairEstimate { get; init; }
    public IReadOnlyCollection<MaintenanceCoordinationAttachment> Attachments { get; init; } = [];
}

public sealed class MaintenanceCoordinationEstimate
{
    public int VersionNumber { get; init; }
    public decimal LaborCost { get; init; }
    public decimal PartsCost { get; init; }
    public decimal AdditionalCost { get; init; }
    public decimal TotalCost { get; init; }
    public string? Notes { get; init; }
    public string Status { get; init; } = string.Empty;
}

public sealed class MaintenanceCoordinationAttachment
{
    public Guid AttachmentId { get; init; }
    public string ContentType { get; init; } = string.Empty;
    public long FileSize { get; init; }
}

[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed class MaintenanceCoordinationAgentResponse
{
    [JsonRequired] public Guid MaintenanceRequestId { get; init; }
    [JsonRequired] public MaintenanceCoordinationResult Result { get; init; } = new();
    [JsonRequired] public MaintenanceCoordinationExecutionMetadata ExecutionMetadata { get; init; } = new();
}

[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed class MaintenanceCoordinationResult
{
    [JsonRequired] public string? SuggestedCategory { get; init; }
    [JsonRequired] public string CategoryConfidence { get; init; } = string.Empty;
    [JsonRequired] public string? SuggestedPriority { get; init; }
    [JsonRequired] public string PriorityConfidence { get; init; } = string.Empty;
    // Required work category, never a verified skill of an individual technician.
    [JsonRequired] public string? RecommendedTechnicianCategory { get; init; }
    [JsonRequired] public string? NextAction { get; init; }
    [JsonRequired] public IReadOnlyCollection<MaintenanceCoordinationValidationFlag> ValidationFlags { get; init; } = [];
    [JsonRequired] public string Rationale { get; init; } = string.Empty;
    [JsonRequired] public bool RequiresHumanReview { get; init; }
    [JsonRequired] public string AgentVersion { get; init; } = string.Empty;
}

[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed class MaintenanceCoordinationValidationFlag
{
    [JsonRequired] public string Code { get; init; } = string.Empty;
    [JsonRequired] public string Message { get; init; } = string.Empty;
}

[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed class MaintenanceCoordinationExecutionMetadata
{
    [JsonRequired] public IReadOnlyCollection<string> ExecutedSteps { get; init; } = [];
}
