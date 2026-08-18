namespace RentFlow.Api.Services;

public enum ApplicationDocumentServiceError
{
    Validation,
    NotFound,
    Conflict
}

public sealed class ApplicationDocumentServiceException : Exception
{
    private ApplicationDocumentServiceException(
        ApplicationDocumentServiceError error,
        string message)
        : base(message)
    {
        Error = error;
    }

    public ApplicationDocumentServiceError Error { get; }

    public static ApplicationDocumentServiceException Validation(string message) =>
        new(ApplicationDocumentServiceError.Validation, message);

    public static ApplicationDocumentServiceException NotFound(string message) =>
        new(ApplicationDocumentServiceError.NotFound, message);

    public static ApplicationDocumentServiceException Conflict(string message) =>
        new(ApplicationDocumentServiceError.Conflict, message);
}
