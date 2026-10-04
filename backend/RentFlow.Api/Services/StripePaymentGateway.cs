using Microsoft.Extensions.Options;
using RentFlow.Api.Configuration;
using RentFlow.Api.Services.Interfaces;
using Stripe;

namespace RentFlow.Api.Services;

public sealed class StripePaymentGateway(IOptions<StripePaymentOptions> options)
    : IStripePaymentGateway
{
    public async Task<StripePaymentIntentResult> CreateAsync(
        StripePaymentIntentRequest request,
        CancellationToken cancellationToken = default)
    {
        var client = CreateClient();
        try
        {
            var intent = await client.V1.PaymentIntents.CreateAsync(
                new PaymentIntentCreateOptions
                {
                    Amount = request.AmountMinorUnits,
                    Currency = request.Currency,
                    CaptureMethod = "automatic",
                    AutomaticPaymentMethods = new PaymentIntentAutomaticPaymentMethodsOptions
                    {
                        Enabled = true
                    },
                    Metadata = new Dictionary<string, string>(request.Metadata)
                },
                new RequestOptions { IdempotencyKey = request.IdempotencyKey },
                cancellationToken);
            return Map(intent);
        }
        catch (Exception ex) when (IsProviderFailure(ex, cancellationToken))
        {
            throw StripeGatewayException.For(ex);
        }
    }

    public async Task<StripePaymentIntentResult> RetrieveAsync(
        string paymentIntentId,
        CancellationToken cancellationToken = default)
    {
        var client = CreateClient();
        try
        {
            var intent = await client.V1.PaymentIntents.GetAsync(
                paymentIntentId,
                cancellationToken: cancellationToken);
            return Map(intent);
        }
        catch (Exception ex) when (IsProviderFailure(ex, cancellationToken))
        {
            throw StripeGatewayException.For(ex);
        }
    }

    private StripeClient CreateClient()
    {
        var secretKey = options.Value.SecretKey;
        if (string.IsNullOrWhiteSpace(secretKey)
            || !secretKey.StartsWith("sk_test_", StringComparison.Ordinal))
        {
            throw new StripeGatewayException(
                StripeGatewayError.Configuration,
                "Stripe test-mode payment service is unavailable.");
        }

        return new StripeClient(secretKey);
    }

    private static StripePaymentIntentResult Map(PaymentIntent intent) => new(
        intent.Id,
        intent.ClientSecret,
        intent.Status,
        intent.Amount,
        intent.Currency,
        intent.Metadata ?? new Dictionary<string, string>());

    private static bool IsProviderFailure(Exception exception, CancellationToken cancellationToken) =>
        exception is StripeException or HttpRequestException
        || exception is TaskCanceledException && !cancellationToken.IsCancellationRequested;
}

public enum StripeGatewayError
{
    Configuration,
    Temporary,
    Provider
}

public sealed class StripeGatewayException(
    StripeGatewayError error,
    string message) : Exception(message)
{
    public StripeGatewayError Error { get; } = error;

    public static StripeGatewayException For(Exception exception) => exception switch
    {
        HttpRequestException or TaskCanceledException =>
            new(StripeGatewayError.Temporary, "Stripe is temporarily unavailable."),
        StripeException stripe when stripe.StripeError?.Type == "api_connection_error" =>
            new(StripeGatewayError.Temporary, "Stripe is temporarily unavailable."),
        _ => new(StripeGatewayError.Provider, "Stripe could not process the request.")
    };
}
