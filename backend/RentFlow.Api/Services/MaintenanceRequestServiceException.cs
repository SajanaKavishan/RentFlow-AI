namespace RentFlow.Api.Services;

public enum MaintenanceRequestServiceError
{
    Validation,
    Forbidden,
    NotFound,
    Conflict
}

public sealed class MaintenanceRequestServiceException : Exception
{
    private MaintenanceRequestServiceException(
        MaintenanceRequestServiceError error,
        string message)
        : base(message)
    {
        Error = error;
    }

    public MaintenanceRequestServiceError Error { get; }

    public static MaintenanceRequestServiceException Validation(string message) =>
        new(MaintenanceRequestServiceError.Validation, message);

    public static MaintenanceRequestServiceException Forbidden(string message) =>
        new(MaintenanceRequestServiceError.Forbidden, message);

    public static MaintenanceRequestServiceException NotFound(string message) =>
        new(MaintenanceRequestServiceError.NotFound, message);

    public static MaintenanceRequestServiceException Conflict(string message) =>
        new(MaintenanceRequestServiceError.Conflict, message);
}
