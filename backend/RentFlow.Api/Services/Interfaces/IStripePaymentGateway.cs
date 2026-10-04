namespace RentFlow.Api.Services.Interfaces;

public interface IStripePaymentGateway
{
    Task<StripePaymentIntentResult> CreateAsync(
        StripePaymentIntentRequest request,
        CancellationToken cancellationToken = default);

    Task<StripePaymentIntentResult> RetrieveAsync(
        string paymentIntentId,
        CancellationToken cancellationToken = default);
}

public sealed record StripePaymentIntentRequest(
    long AmountMinorUnits,
    string Currency,
    string IdempotencyKey,
    IReadOnlyDictionary<string, string> Metadata);

public sealed record StripePaymentIntentResult(
    string Id,
    string? ClientSecret,
    string Status,
    long AmountMinorUnits,
    string Currency,
    IReadOnlyDictionary<string, string> Metadata);
