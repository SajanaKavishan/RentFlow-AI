namespace RentFlow.Api.Services;

public enum ApplicationValidationError
{
    Validation,
    NotFound,
    Conflict
}

public class ApplicationValidationException : Exception
{
    public ApplicationValidationException(ApplicationValidationError error, string message)
        : base(message)
    {
        Error = error;
    }

    public ApplicationValidationError Error { get; }
}
