namespace RentFlow.Api.Models;

/// <summary>
/// Represents one scheduled rent payment for a lease agreement.
/// </summary>
public class RentScheduleItem
{
    public Guid Id { get; set; } = Guid.NewGuid();

    public Guid LeaseAgreementId { get; set; }

    public DateOnly DueDate { get; set; }

    public decimal Amount { get; set; }

    public RentScheduleStatus Status { get; set; } = RentScheduleStatus.Pending;

    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;

    public DateTimeOffset? UpdatedAt { get; set; }

    public LeaseAgreement LeaseAgreement { get; set; } = null!;
}