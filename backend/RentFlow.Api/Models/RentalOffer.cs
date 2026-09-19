namespace RentFlow.Api.Models;

/// <summary>
/// Represents a rental offer created for an approved rental application.
/// </summary>
public class RentalOffer
{
    public Guid Id { get; set; } = Guid.NewGuid();

    public Guid RentalApplicationId { get; set; }

    public Guid TenantId { get; set; }

    public Guid PropertyId { get; set; }

    public decimal MonthlyRent { get; set; }

    public decimal SecurityDeposit { get; set; }

    public DateOnly ProposedStartDate { get; set; }

    public DateOnly ProposedEndDate { get; set; }

    public DateTimeOffset ExpiresAt { get; set; }

    public RentalOfferStatus Status { get; set; } = RentalOfferStatus.Pending;

    public string? LandlordNote { get; set; }

    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;

    public DateTimeOffset? UpdatedAt { get; set; }

    public RentalApplication RentalApplication { get; set; } = null!;
}