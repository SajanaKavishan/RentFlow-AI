using System.ComponentModel.DataAnnotations;

namespace RentFlow.Api.DTOs.RentalOffers;

public class CreateRentalOfferDto
{
    [Required]
    public Guid RentalApplicationId { get; set; }

    [Range(0.01, double.MaxValue, ErrorMessage = "Monthly rent must be greater than zero.")]
    public decimal MonthlyRent { get; set; }

    [Range(0, double.MaxValue, ErrorMessage = "Security deposit cannot be negative.")]
    public decimal SecurityDeposit { get; set; }

    [Required]
    public DateOnly ProposedStartDate { get; set; }

    [Required]
    public DateOnly ProposedEndDate { get; set; }

    [Required]
    public DateTimeOffset ExpiresAt { get; set; }

    [MaxLength(1000)]
    public string? LandlordNote { get; set; }
}