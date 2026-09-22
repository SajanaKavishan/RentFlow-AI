namespace RentFlow.Api.Models;

/// <summary>
/// Represents one persisted step in a maintenance coordination workflow.
/// </summary>
public class MaintenanceCoordinationStep
{
    public Guid Id { get; set; } = Guid.NewGuid();

    public Guid WorkflowId { get; set; }

    public string StepName { get; set; } = string.Empty;

    public int StepOrder { get; set; }

    public MaintenanceCoordinationStepStatus Status { get; set; } = MaintenanceCoordinationStepStatus.Pending;

    public string? InputSummary { get; set; }

    public string? OutputSummary { get; set; }

    public string? ValidationSummary { get; set; }

    public string? ErrorMessage { get; set; }

    public DateTimeOffset? StartedAt { get; set; }

    public DateTimeOffset? CompletedAt { get; set; }

    public MaintenanceCoordinationWorkflow Workflow { get; set; } = null!;
}
