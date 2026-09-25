namespace RentFlow.Api.Services;

public enum PricingAnalysisError
{
    Validation,
    NotFound
}

public sealed class PricingAnalysisException(PricingAnalysisError error, string message)
    : Exception(message)
{
    public PricingAnalysisError Error { get; } = error;
}
