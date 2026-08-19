using RentFlow.Api.Models;

namespace RentFlow.Api.DTOs.ApplicationValidation;

/// <summary>
/// Represents a validation workflow and its ordered step state.
/// </summary>
public class ApplicationValidationWorkflowResponseDto
{
    public Guid Id { get; set; }

    public Guid ApplicationId { get; set; }

    public string Objective { get; set; } = string.Empty;

    public ApplicationValidationWorkflowStatus Status { get; set; }

    public int CurrentStep { get; set; }

    public decimal? CompletenessScore { get; set; }

    public string? Recommendation { get; set; }

    public bool RequiresHumanApproval { get; set; }

    public DateTimeOffset CreatedAt { get; set; }

    public DateTimeOffset UpdatedAt { get; set; }

    public IReadOnlyCollection<ApplicationValidationStepResponseDto> Steps { get; set; }
        = Array.Empty<ApplicationValidationStepResponseDto>();
}
