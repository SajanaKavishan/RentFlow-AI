namespace RentFlow.Api.Models;

public sealed class TenantPropertyPreference
{
    public Guid UserId { get; set; }

    public string? PreferredCity { get; set; }

    public decimal? MaximumMonthlyRent { get; set; }

    public int? MinimumBedrooms { get; set; }

    public int? MinimumBathrooms { get; set; }

    public string[] PreferredAmenities { get; set; } = [];

    public DateTimeOffset UpdatedAt { get; set; }
}
