namespace RentFlow.Api.DTOs.PropertyMatching;

public sealed class PropertyMatchingRequest
{
    public string? PreferredCity { get; set; }

    public decimal? MaximumMonthlyRent { get; set; }

    public int? MinimumBedrooms { get; set; }

    public int? MinimumBathrooms { get; set; }

    public List<string> PreferredAmenities { get; set; } = [];
}