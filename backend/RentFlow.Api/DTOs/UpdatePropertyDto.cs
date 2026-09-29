using System.ComponentModel.DataAnnotations;

namespace RentFlow.Api.DTOs;

public class UpdatePropertyDto : IValidatableObject
{
    [Required]
    [MaxLength(200)]
    public string Title { get; set; } = string.Empty;

    [Required]
    [MaxLength(2000)]
    public string Description { get; set; } = string.Empty;

    [Required]
    [MaxLength(500)]
    public string Address { get; set; } = string.Empty;

    [Required]
    [MaxLength(100)]
    public string City { get; set; } = string.Empty;

    [Range(-90d, 90d)]
    public double? Latitude { get; set; }

    [Range(-180d, 180d)]
    public double? Longitude { get; set; }

    [MaxLength(255)]
    public string? GooglePlaceId { get; set; }

    [Range(0.01, double.MaxValue)]
    public decimal MonthlyRent { get; set; }

    [Range(0, int.MaxValue)]
    public int Bedrooms { get; set; }

    [Range(0, int.MaxValue)]
    public int Bathrooms { get; set; }

    [Range(0.01, double.MaxValue)]
    public decimal? Area { get; set; }

    [RegularExpression("^(sqft|sqm|perch|acre)$")]
    public string? AreaUnit { get; set; }

    [RegularExpression("^(FloorArea|LandArea)$")]
    public string? AreaType { get; set; }

    public DateOnly? AvailableFrom { get; set; }

    public bool IsAvailable { get; set; }

    public List<string> Amenities { get; set; } = new();

    public IEnumerable<ValidationResult> Validate(ValidationContext validationContext)
    {
        if (Latitude.HasValue != Longitude.HasValue)
        {
            yield return new ValidationResult(
                "Latitude and longitude must be provided together.",
                new[] { nameof(Latitude), nameof(Longitude) });
        }

        if (!string.IsNullOrWhiteSpace(GooglePlaceId) &&
            (!Latitude.HasValue || !Longitude.HasValue))
        {
            yield return new ValidationResult(
                "A Google place ID requires latitude and longitude.",
                new[] { nameof(GooglePlaceId) });
        }

        if (AreaType == "FloorArea" &&
            AreaUnit is "perch" or "acre")
        {
            yield return new ValidationResult(
                "Floor area must use square feet or square metres.",
                new[] { nameof(AreaType), nameof(AreaUnit) });
        }

        if (!Area.HasValue &&
            (!string.IsNullOrWhiteSpace(AreaType) ||
             !string.IsNullOrWhiteSpace(AreaUnit)))
        {
            yield return new ValidationResult(
                "Area type and unit require an area value.",
                new[] { nameof(Area), nameof(AreaType), nameof(AreaUnit) });
        }
    }
}
