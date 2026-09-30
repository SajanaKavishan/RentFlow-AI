using System.ComponentModel.DataAnnotations;
using RentFlow.Api.Models;
using RentFlow.Api.Services;

namespace RentFlow.Api.DTOs;

/// <summary>
/// Presence-safe contract used by the current listing editor. The legacy PUT
/// contract intentionally has no listing-preference properties.
/// </summary>
public sealed class UpdatePropertyListingDto : UpdatePropertyDto, IValidatableObject
{
    [Range(typeof(decimal), "0", "9999999999999999.99")]
    public decimal? AdvertisedSecurityDeposit { get; set; }

    [Range(1, 120)]
    public int? PreferredLeaseTermMonths { get; set; }

    public PetPolicyStatus? PetPolicy { get; set; }

    [MaxLength(500)]
    public string? PetPolicyNotes { get; set; }

    public List<string>? IncludedUtilities { get; set; }

    public List<PropertyAmenityInputDto>? AmenityDetails { get; set; }

    public new IEnumerable<ValidationResult> Validate(ValidationContext validationContext)
    {
        foreach (var result in base.Validate(validationContext))
        {
            yield return result;
        }

        foreach (var result in PropertyListingPreferenceValidator.Validate(
            PetPolicy, PetPolicyNotes, IncludedUtilities))
        {
            yield return result;
        }
    }
}
