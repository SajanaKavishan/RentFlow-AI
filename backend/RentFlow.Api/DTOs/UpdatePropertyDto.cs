using System.ComponentModel.DataAnnotations;

namespace RentFlow.Api.DTOs;

public class UpdatePropertyDto
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

    public bool IsAvailable { get; set; }

    public List<string> Amenities { get; set; } = new();
}
