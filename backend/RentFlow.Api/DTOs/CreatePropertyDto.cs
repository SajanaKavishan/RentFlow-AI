using System.ComponentModel.DataAnnotations;
using RentFlow.Api.Models;
using RentFlow.Api.Services;

namespace RentFlow.Api.DTOs;

public class CreatePropertyDto : IValidatableObject
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

    [Range(typeof(decimal), "0", "9999999999999999.99")]
    public decimal? AdvertisedSecurityDeposit { get; set; }

    [Range(1, 120)]
    public int? PreferredLeaseTermMonths { get; set; }

    public PetPolicyStatus? PetPolicy { get; set; }

    [MaxLength(500)]
    public string? PetPolicyNotes { get; set; }

    public List<string>? IncludedUtilities { get; set; }

    [Range(0, int.MaxValue)]
    public int Bedrooms { get; set; }

    [Range(0, int.MaxValue)]
    public int Bathrooms { get; set; }

    [Required]
    [Range(0.01, double.MaxValue)]
    public decimal? Area { get; set; }

    [Required]
    [RegularExpression("^(sqft|sqm|perch|acre)$")]
    public string AreaUnit { get; set; } = "sqft";

    [Required]
    [RegularExpression("^(FloorArea|LandArea)$")]
    public string? AreaType { get; set; }

    public DateOnly? AvailableFrom { get; set; }

    public bool IsAvailable { get; set; } = true;

    public List<string> Amenities { get; set; } = new();

    public List<PropertyAmenityInputDto>? AmenityDetails { get; set; }

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

        foreach (var result in PropertyListingPreferenceValidator.Validate(
            PetPolicy, PetPolicyNotes, IncludedUtilities))
        {
            yield return result;
        }
    }
}
