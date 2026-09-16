using RentFlow.Api.Models;

namespace RentFlow.Api.DTOs.RentalOffers;

public class RentalOfferResponseDto
{
    public Guid Id { get; set; }

    public Guid RentalApplicationId { get; set; }

    public Guid TenantId { get; set; }

    public Guid PropertyId { get; set; }

    public decimal MonthlyRent { get; set; }

    public decimal SecurityDeposit { get; set; }

    public DateOnly ProposedStartDate { get; set; }

    public DateOnly ProposedEndDate { get; set; }

    public DateTimeOffset ExpiresAt { get; set; }

    public RentalOfferStatus Status { get; set; }

    public string? LandlordNote { get; set; }

    public DateTimeOffset CreatedAt { get; set; }

    public DateTimeOffset? UpdatedAt { get; set; }
}