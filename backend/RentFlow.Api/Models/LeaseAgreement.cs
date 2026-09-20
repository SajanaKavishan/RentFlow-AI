namespace RentFlow.Api.Models;

/// <summary>
/// Represents a lease agreement created from an accepted rental offer.
/// </summary>
public class LeaseAgreement
{
    public Guid Id { get; set; } = Guid.NewGuid();

    public Guid RentalOfferId { get; set; }

    public Guid TenantId { get; set; }

    public Guid PropertyId { get; set; }

    public decimal MonthlyRent { get; set; }

    public decimal SecurityDeposit { get; set; }

    public DateOnly StartDate { get; set; }

    public DateOnly EndDate { get; set; }

    public LeaseAgreementStatus Status { get; set; } = LeaseAgreementStatus.Pending;

    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;

    public DateTimeOffset? UpdatedAt { get; set; }

    public RentalOffer RentalOffer { get; set; } = null!;
}