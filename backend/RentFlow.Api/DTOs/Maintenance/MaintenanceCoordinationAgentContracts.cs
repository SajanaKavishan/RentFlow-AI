using System.Text.Json.Serialization;

namespace RentFlow.Api.DTOs.Maintenance;

public sealed class MaintenanceCoordinationAgentRequest
{
    public Guid MaintenanceRequestId { get; init; }
    public string Title { get; init; } = string.Empty;
    public string Description { get; init; } = string.Empty;
    public string Category { get; init; } = string.Empty;
    public string Priority { get; init; } = string.Empty;
    public string CurrentStatus { get; init; } = string.Empty;
    public Guid? AssignedTechnicianId { get; init; }
    public MaintenanceCoordinationEstimate? RepairEstimate { get; init; }
    public IReadOnlyCollection<MaintenanceCoordinationAttachment> Attachments { get; init; } = [];
}

public sealed class MaintenanceCoordinationEstimate
{
    public decimal Amount { get; init; }
    public string Currency { get; init; } = "USD";
    public string? Notes { get; init; }
}

public sealed class MaintenanceCoordinationAttachment
{
    public Guid AttachmentId { get; init; }
    public string FileName { get; init; } = string.Empty;
    public string ContentType { get; init; } = string.Empty;
}

public sealed class MaintenanceCoordinationAgentResponse
{
    public Guid MaintenanceRequestId { get; init; }
    public MaintenanceCoordinationResult Result { get; init; } = new();
    public MaintenanceCoordinationExecutionMetadata ExecutionMetadata { get; init; } = new();
}

public sealed class MaintenanceCoordinationResult
{
    public string RecommendedCategory { get; init; } = string.Empty;
    public string RecommendedPriority { get; init; } = string.Empty;
    public string NextAction { get; init; } = string.Empty;
    public string Reasoning { get; init; } = string.Empty;
    public IReadOnlyCollection<string> Warnings { get; init; } = [];
    public string AgentVersion { get; init; } = string.Empty;
}

public sealed class MaintenanceCoordinationExecutionMetadata
{
    public IReadOnlyCollection<string> ExecutedSteps { get; init; } = [];
}