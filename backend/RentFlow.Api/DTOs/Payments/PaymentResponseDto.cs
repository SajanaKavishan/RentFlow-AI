using RentFlow.Api.Models;

namespace RentFlow.Api.DTOs.Payments;

public class PaymentResponseDto
{
    public Guid Id { get; set; }

    public Guid RentScheduleItemId { get; set; }

    public Guid TenantId { get; set; }

    public decimal Amount { get; set; }

    public string PaymentMethod { get; set; } = string.Empty;

    public string? TransactionReference { get; set; }

    public PaymentStatus Status { get; set; }

    public DateTimeOffset? PaidAt { get; set; }

    public DateTimeOffset CreatedAt { get; set; }

    public DateTimeOffset? UpdatedAt { get; set; }
}