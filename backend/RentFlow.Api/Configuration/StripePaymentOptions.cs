namespace RentFlow.Api.Configuration;

public sealed class StripePaymentOptions
{
    public const string SectionName = "Payments";

    public string Currency { get; set; } = "LKR";

    // Set through user-secrets or environment variables when Stripe is enabled.
    public string? SecretKey { get; set; }
    public string? PublishableKey { get; set; }
    public string? WebhookSecret { get; set; }

    public bool HasValidCurrency => Currency == "LKR";

    public string StripeCurrency => "lkr";

    public static long ToStripeMinorUnits(decimal amountLkr)
    {
        if (amountLkr <= 0 || decimal.Round(amountLkr, 2) != amountLkr)
        {
            throw new ArgumentOutOfRangeException(nameof(amountLkr),
                "LKR amount must be positive and have at most two decimal places.");
        }

        return checked((long)(amountLkr * 100m));
    }
}
