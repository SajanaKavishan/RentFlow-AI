namespace RentFlow.Api.Models;

/// <summary>
/// Represents a payment made for a scheduled rent item.
/// </summary>
public class Payment
{
    public Guid Id { get; set; } = Guid.NewGuid();

    public Guid RentScheduleItemId { get; set; }

    public Guid TenantId { get; set; }

    public decimal Amount { get; set; }

    public PaymentProvider Provider { get; set; } = PaymentProvider.Manual;

    // Stripe's PaymentIntent ID is an identifier, never a client secret.
    public string? StripePaymentIntentId { get; set; }

    public string PaymentMethod { get; set; } = string.Empty;

    public string? TransactionReference { get; set; }

    public PaymentStatus Status { get; set; } = PaymentStatus.Pending;

    public DateTimeOffset? PaidAt { get; set; }

    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;

    public DateTimeOffset? UpdatedAt { get; set; }

    public RentScheduleItem RentScheduleItem { get; set; } = null!;
}
