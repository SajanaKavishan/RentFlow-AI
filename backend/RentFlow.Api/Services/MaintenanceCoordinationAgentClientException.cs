namespace RentFlow.Api.Services;

public enum MaintenanceCoordinationAgentClientError
{
    Configuration,
    ServiceUnavailable,
    Timeout,
    UpstreamFailure,
    MalformedResponse
}

public sealed class MaintenanceCoordinationAgentClientException(
    MaintenanceCoordinationAgentClientError error,
    string message,
    Exception? innerException = null) : Exception(message, innerException)
{
    public MaintenanceCoordinationAgentClientError Error { get; } = error;
}