namespace RentFlow.Api.DTOs.PropertyMatching;

public sealed class TenantPropertyPreferenceResponse
{
    public bool IsConfigured { get; init; }

    public string? PreferredCity { get; init; }

    public decimal? MaximumMonthlyRent { get; init; }

    public int? MinimumBedrooms { get; init; }

    public int? MinimumBathrooms { get; init; }

    public List<string> PreferredAmenities { get; init; } = [];

    public DateTimeOffset? UpdatedAt { get; init; }
}
