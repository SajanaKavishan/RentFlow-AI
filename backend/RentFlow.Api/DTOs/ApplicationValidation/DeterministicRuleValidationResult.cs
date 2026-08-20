namespace RentFlow.Api.DTOs.ApplicationValidation;

public class DeterministicRuleValidationResult
{
    public bool Passed { get; init; }

    public IReadOnlyCollection<string> PassedRules { get; init; } = Array.Empty<string>();

    public IReadOnlyCollection<string> FailedRules { get; init; } = Array.Empty<string>();

    public IReadOnlyCollection<string> Warnings { get; init; } = Array.Empty<string>();
}
