namespace RentFlow.Api.Models;

/// <summary>
/// Represents an individual agent or deterministic validation step in a workflow.
/// </summary>
public class ApplicationValidationStep
{
    public Guid Id { get; set; } = Guid.NewGuid();

    public Guid WorkflowId { get; set; }

    public string AgentName { get; set; } = string.Empty;

    public int StepOrder { get; set; }

    public ApplicationValidationStepStatus Status { get; set; } = ApplicationValidationStepStatus.Pending;

    public string? InputSummary { get; set; }

    /// <summary>
    /// Gets or sets the serialized JSON result. It remains a string so storage is provider-independent.
    /// </summary>
    public string? ResultJson { get; set; }

    public string? ErrorMessage { get; set; }

    public DateTimeOffset? StartedAt { get; set; }

    public DateTimeOffset? CompletedAt { get; set; }

    public ApplicationValidationWorkflow Workflow { get; set; } = null!;
}
