using System.Text.Json;
using RentFlow.Api.Models;

namespace RentFlow.Api.DTOs.ApplicationValidation;

/// <summary>
/// Represents the externally relevant state of a validation workflow step.
/// </summary>
public class ApplicationValidationStepResponseDto
{
    public string AgentName { get; set; } = string.Empty;

    public int StepOrder { get; set; }

    public ApplicationValidationStepStatus Status { get; set; }

    public JsonElement? Result { get; set; }

    public string? ErrorMessage { get; set; }

    public DateTimeOffset? StartedAt { get; set; }

    public DateTimeOffset? CompletedAt { get; set; }
}
