namespace RentFlow.Api.Services;

public enum RentScheduleServiceError
{
    Validation,
    NotFound,
    Conflict
}

public sealed class RentScheduleServiceException : Exception
{
    private RentScheduleServiceException(
        RentScheduleServiceError error,
        string message)
        : base(message)
    {
        Error = error;
    }

    public RentScheduleServiceError Error { get; }

    public static RentScheduleServiceException Validation(string message) =>
        new(RentScheduleServiceError.Validation, message);

    public static RentScheduleServiceException NotFound(string message) =>
        new(RentScheduleServiceError.NotFound, message);

    public static RentScheduleServiceException Conflict(string message) =>
        new(RentScheduleServiceError.Conflict, message);
}