namespace RentFlow.Api.DTOs.ApplicationValidation;

public class ApplicationValidationSummaryDto
{
    public decimal CompletenessScore { get; init; }

    public string Recommendation { get; init; } = string.Empty;

    public bool RequiresHumanApproval { get; init; }

    public ApplicationDataValidationResult ApplicationData { get; init; } = new();

    public DocumentValidationResult Documents { get; init; } = new();

    public DeterministicRuleValidationResult DeterministicRules { get; init; } = new();
}
