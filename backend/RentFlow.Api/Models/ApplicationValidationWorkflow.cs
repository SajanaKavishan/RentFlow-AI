namespace RentFlow.Api.Models;

/// <summary>
/// Represents one validation run for a rental application.
/// </summary>
public class ApplicationValidationWorkflow
{
    public Guid Id { get; set; } = Guid.NewGuid();

    public Guid ApplicationId { get; set; }

    public string Objective { get; set; } = string.Empty;

    public ApplicationValidationWorkflowStatus Status { get; set; } = ApplicationValidationWorkflowStatus.Pending;

    public int CurrentStep { get; set; }

    public decimal? CompletenessScore { get; set; }

    public string? Recommendation { get; set; }

    public bool RequiresHumanApproval { get; set; } = true;

    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;

    public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.UtcNow;

    public RentalApplication Application { get; set; } = null!;

    public ICollection<ApplicationValidationStep> Steps { get; set; } = new List<ApplicationValidationStep>();
}
