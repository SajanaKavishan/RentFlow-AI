using System.Text.Json;
using Microsoft.Extensions.Options;
using RentFlow.Api.Configuration;
using RentFlow.Api.Services.Interfaces;
using Stripe;

namespace RentFlow.Api.Services;

public sealed class StripeWebhookVerifier(IOptions<StripePaymentOptions> options)
    : IStripeWebhookVerifier
{
    public StripeWebhookEvent Verify(string rawBody, string signatureHeader)
    {
        if (string.IsNullOrWhiteSpace(signatureHeader))
        {
            throw new StripeWebhookException(StripeWebhookError.InvalidSignature);
        }

        var secret = options.Value.WebhookSecret;
        if (string.IsNullOrWhiteSpace(secret))
        {
            throw new StripeWebhookException(StripeWebhookError.NotConfigured);
        }

        try
        {
            EventUtility.ValidateSignature(rawBody, signatureHeader, secret);
        }
        catch (Exception ex) when (ex is StripeException or FormatException
            or ArgumentException or KeyNotFoundException)
        {
            throw new StripeWebhookException(StripeWebhookError.InvalidSignature);
        }

        try
        {
            using var document = JsonDocument.Parse(rawBody);
            var root = document.RootElement;
            if (!root.TryGetProperty("type", out var eventType)
                || eventType.ValueKind != JsonValueKind.String
                || string.IsNullOrWhiteSpace(eventType.GetString()))
            {
                throw new StripeWebhookException(StripeWebhookError.MalformedEvent);
            }

            string? intentId = null;
            if (root.TryGetProperty("data", out var data)
                && data.ValueKind == JsonValueKind.Object
                && data.TryGetProperty("object", out var eventObject)
                && eventObject.ValueKind == JsonValueKind.Object
                && eventObject.TryGetProperty("id", out var id)
                && id.ValueKind == JsonValueKind.String)
            {
                intentId = id.GetString();
            }

            return new StripeWebhookEvent(eventType.GetString()!, intentId);
        }
        catch (JsonException)
        {
            throw new StripeWebhookException(StripeWebhookError.MalformedEvent);
        }
    }
}

public enum StripeWebhookError
{
    InvalidSignature,
    NotConfigured,
    MalformedEvent
}

public sealed class StripeWebhookException(StripeWebhookError error) : Exception
{
    public StripeWebhookError Error { get; } = error;
}
