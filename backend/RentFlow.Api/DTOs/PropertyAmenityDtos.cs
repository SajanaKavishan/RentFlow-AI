using System.ComponentModel.DataAnnotations;

namespace RentFlow.Api.DTOs;

public sealed class PropertyAmenityInputDto : IValidatableObject
{
    [MaxLength(100)]
    public string? CanonicalKey { get; set; }

    [MaxLength(100)]
    public string? CustomName { get; set; }

    public IEnumerable<ValidationResult> Validate(ValidationContext validationContext)
    {
        var hasCanonical = !string.IsNullOrWhiteSpace(CanonicalKey);
        var hasCustom = !string.IsNullOrWhiteSpace(CustomName);
        if (hasCanonical == hasCustom)
        {
            yield return new ValidationResult(
                "Provide either a canonical amenity key or a custom amenity name.",
                [nameof(CanonicalKey), nameof(CustomName)]);
        }
    }
}

public sealed class PropertyAmenityResponseDto
{
    public string? CanonicalKey { get; set; }

    public string Name { get; set; } = string.Empty;
}
