namespace RentFlow.Api.Services.Interfaces;

// The implementation and PaymentIntent creation belong to Stripe Slice 2.
public interface IStripePaymentGateway
{
    Task<StripePaymentIntentResult> CreateAsync(
        long amountMinorUnits,
        string currency,
        string idempotencyKey,
        CancellationToken cancellationToken = default);
}

public sealed record StripePaymentIntentResult(string Id, string ClientSecret);
