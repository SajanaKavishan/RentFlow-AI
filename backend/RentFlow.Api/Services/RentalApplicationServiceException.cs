namespace RentFlow.Api.Services;

public enum RentalApplicationServiceError
{
    Validation,
    NotFound,
    Conflict
}

public sealed class RentalApplicationServiceException : Exception
{
    private RentalApplicationServiceException(
        RentalApplicationServiceError error,
        string message)
        : base(message)
    {
        Error = error;
    }

    public RentalApplicationServiceError Error { get; }

    public static RentalApplicationServiceException Validation(string message) =>
        new(RentalApplicationServiceError.Validation, message);

    public static RentalApplicationServiceException NotFound(string message) =>
        new(RentalApplicationServiceError.NotFound, message);

    public static RentalApplicationServiceException Conflict(string message) =>
        new(RentalApplicationServiceError.Conflict, message);
}
