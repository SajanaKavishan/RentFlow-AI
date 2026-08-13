namespace RentFlow.Api.Services;

public enum ViewingServiceError
{
    Validation,
    NotFound,
    Conflict
}

public sealed class ViewingServiceException : Exception
{
    private ViewingServiceException(ViewingServiceError error, string message)
        : base(message)
    {
        Error = error;
    }

    public ViewingServiceError Error { get; }

    public static ViewingServiceException Validation(string message) =>
        new(ViewingServiceError.Validation, message);

    public static ViewingServiceException NotFound(string message) =>
        new(ViewingServiceError.NotFound, message);

    public static ViewingServiceException Conflict(string message) =>
        new(ViewingServiceError.Conflict, message);
}
