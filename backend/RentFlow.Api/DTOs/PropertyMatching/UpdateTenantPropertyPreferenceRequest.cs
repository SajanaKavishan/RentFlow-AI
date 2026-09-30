using System.ComponentModel.DataAnnotations;

namespace RentFlow.Api.DTOs.PropertyMatching;

public sealed class UpdateTenantPropertyPreferenceRequest
{
    [StringLength(100)]
    public string? PreferredCity { get; init; }

    [Range(typeof(decimal), "0", "9999999999999999")]
    public decimal? MaximumMonthlyRent { get; init; }

    [Range(0, 20)]
    public int? MinimumBedrooms { get; init; }

    [Range(0, 20)]
    public int? MinimumBathrooms { get; init; }

    [MaxLength(20)]
    public List<string> PreferredAmenities { get; init; } = [];
}
