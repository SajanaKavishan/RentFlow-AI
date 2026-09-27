namespace RentFlow.Api.DTOs;

public class PropertyResponseDto
{
    public Guid Id { get; set; }

    public Guid LandlordId { get; set; }

    public string Title { get; set; } = string.Empty;

    public string Description { get; set; } = string.Empty;

    public string Address { get; set; } = string.Empty;

    public string City { get; set; } = string.Empty;

    public double? Latitude { get; set; }

    public double? Longitude { get; set; }

    public string? GooglePlaceId { get; set; }

    public decimal MonthlyRent { get; set; }

    public int Bedrooms { get; set; }

    public int Bathrooms { get; set; }

    public decimal? Area { get; set; }

    public string? AreaUnit { get; set; }

    public bool IsAvailable { get; set; }

    public DateTimeOffset CreatedAt { get; set; }

    public DateTimeOffset? UpdatedAt { get; set; }

    public List<string> Amenities { get; set; } = new();
}
