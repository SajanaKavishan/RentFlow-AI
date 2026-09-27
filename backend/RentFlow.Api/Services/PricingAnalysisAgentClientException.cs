namespace RentFlow.Api.Services;

public enum PricingAnalysisAgentClientError
{
    Configuration,
    Timeout,
    ServiceUnavailable,
    UpstreamFailure,
    MalformedResponse
}

public sealed class PricingAnalysisAgentClientException(
    PricingAnalysisAgentClientError error,
    string message) : Exception(message)
{
    public PricingAnalysisAgentClientError Error { get; } = error;
}
