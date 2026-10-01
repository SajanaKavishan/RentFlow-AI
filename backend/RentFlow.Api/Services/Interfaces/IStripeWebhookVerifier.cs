namespace RentFlow.Api.Services.Interfaces;

public interface IStripeWebhookVerifier
{
    StripeWebhookEvent Verify(string rawBody, string signatureHeader);
}

public sealed record StripeWebhookEvent(string Type, string? PaymentIntentId);
