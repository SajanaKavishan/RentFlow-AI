using RentFlow.Api.Models;

namespace RentFlow.Api.DTOs.Payments;

public sealed record StripeIntentResponseDto(
    Guid PaymentId,
    string? ClientSecret,
    string PublishableKey,
    string Currency,
    decimal Amount,
    PaymentStatus PaymentStatus,
    string Status);

public sealed record StripePaymentStatusDto(
    Guid PaymentId,
    PaymentStatus PaymentStatus,
    string Status,
    DateTimeOffset? PaidAt);
