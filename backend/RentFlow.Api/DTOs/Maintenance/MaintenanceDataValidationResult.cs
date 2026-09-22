namespace RentFlow.Api.DTOs.Maintenance;

public class MaintenanceDataValidationResult
{
    public bool IsValid { get; init; }

    public decimal CompletenessScore { get; init; }

    public IReadOnlyCollection<string> MissingFields { get; init; } = Array.Empty<string>();

    public IReadOnlyCollection<string> Warnings { get; init; } = Array.Empty<string>();
}
