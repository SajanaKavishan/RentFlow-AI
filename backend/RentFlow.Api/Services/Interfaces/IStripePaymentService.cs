using RentFlow.Api.DTOs.Payments;

namespace RentFlow.Api.Services.Interfaces;

public interface IStripePaymentService
{
    Task<StripeIntentResponseDto> CreateOrResumeAsync(
        Guid rentScheduleItemId,
        Guid tenantId,
        CancellationToken cancellationToken = default);

    Task<StripePaymentStatusDto> GetStatusAsync(
        Guid paymentId,
        Guid tenantId,
        CancellationToken cancellationToken = default);

    Task<StripeWebhookProcessingResult> ProcessWebhookAsync(
        string paymentIntentId,
        CancellationToken cancellationToken = default);
}

public enum StripeWebhookProcessingResult
{
    Processed,
    UnknownPaymentIntent
}
