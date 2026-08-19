namespace RentFlow.Api.Services;

public enum ApplicationValidationAgentClientError
{
    Configuration,
    ServiceUnavailable,
    Timeout,
    UpstreamFailure,
    MalformedResponse
}

public class ApplicationValidationAgentClientException(
    ApplicationValidationAgentClientError error,
    string message,
    Exception? innerException = null) : Exception(message, innerException)
{
    public ApplicationValidationAgentClientError Error { get; } = error;
}
