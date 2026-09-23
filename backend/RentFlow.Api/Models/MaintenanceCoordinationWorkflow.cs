namespace RentFlow.Api.Models;

/// <summary>
/// Represents one durable maintenance coordination run for a maintenance request.
/// </summary>
public class MaintenanceCoordinationWorkflow
{
    public Guid Id { get; set; } = Guid.NewGuid();

    public Guid MaintenanceRequestId { get; set; }

    public string Objective { get; set; } = string.Empty;

    public MaintenanceCoordinationWorkflowStatus Status { get; set; } = MaintenanceCoordinationWorkflowStatus.Pending;

    public int CurrentStep { get; set; }

    public string? AgentVersion { get; set; }

    public string? PlanSummary { get; set; }

    public string? ExecutionSummary { get; set; }

    public string? FinalResultJson { get; set; }

    public string? ErrorMessage { get; set; }

    public bool RequiresHumanApproval { get; set; } = true;

    public MaintenanceCoordinationApprovalStatus ApprovalStatus { get; set; } = MaintenanceCoordinationApprovalStatus.Pending;

    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;

    public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.UtcNow;

    public MaintenanceRequest MaintenanceRequest { get; set; } = null!;

    public ICollection<MaintenanceCoordinationStep> Steps { get; set; } = new List<MaintenanceCoordinationStep>();
}
