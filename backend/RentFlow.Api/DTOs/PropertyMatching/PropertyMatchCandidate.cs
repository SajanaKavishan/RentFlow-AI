namespace RentFlow.Api.DTOs.PropertyMatching;

public sealed class PropertyMatchCandidate
{
    public Guid PropertyId { get; set; }

    public string Title { get; set; } = string.Empty;

    public string City { get; set; } = string.Empty;

    public decimal MonthlyRent { get; set; }

    public int Bedrooms { get; set; }

    public int Bathrooms { get; set; }

    public List<string> Amenities { get; set; } = [];

    public int MatchScore { get; set; }

    public List<string> MatchReasons { get; set; } = [];
}