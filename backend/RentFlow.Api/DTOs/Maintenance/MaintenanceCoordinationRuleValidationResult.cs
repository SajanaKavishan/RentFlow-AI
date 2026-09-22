namespace RentFlow.Api.DTOs.Maintenance;

public class MaintenanceCoordinationRuleValidationResult
{
    public bool Passed { get; init; }

    public IReadOnlyCollection<string> PassedRules { get; init; } = Array.Empty<string>();

    public IReadOnlyCollection<string> FailedRules { get; init; } = Array.Empty<string>();

    public IReadOnlyCollection<string> Warnings { get; init; } = Array.Empty<string>();
}
