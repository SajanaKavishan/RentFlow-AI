namespace RentFlow.Api.Models;

/// <summary>
/// Represents one persisted ordered step in a pricing analysis workflow.
/// </summary>
public class PricingAnalysisWorkflowStep
{
    public Guid Id { get; set; } = Guid.NewGuid();

    public Guid WorkflowId { get; set; }

    public string StepName { get; set; } = string.Empty;

    public int StepOrder { get; set; }

    public PricingAnalysisWorkflowStepStatus Status { get; set; } = PricingAnalysisWorkflowStepStatus.Pending;

    public string? OutputSummary { get; set; }

    public string? ResultJson { get; set; }

    public string? ValidationSummary { get; set; }

    public string? ErrorMessage { get; set; }

    public DateTimeOffset? StartedAt { get; set; }

    public DateTimeOffset? CompletedAt { get; set; }

    public PricingAnalysisWorkflow Workflow { get; set; } = null!;
}
