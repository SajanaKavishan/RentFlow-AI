namespace RentFlow.Api.Services;

public enum AuthServiceError
{
    Validation,
    DuplicateEmail,
    InvalidCredentials,
    IncorrectCurrentPassword
}

public sealed class AuthServiceException(AuthServiceError error, string message) : Exception(message)
{
    public AuthServiceError Error { get; } = error;

    public static AuthServiceException Validation(string message) =>
        new(AuthServiceError.Validation, message);

    public static AuthServiceException DuplicateEmail() =>
        new(AuthServiceError.DuplicateEmail, "An account with this email already exists.");

    public static AuthServiceException InvalidCredentials() =>
        new(AuthServiceError.InvalidCredentials, "Invalid email or password.");

    public static AuthServiceException IncorrectCurrentPassword() =>
        new(AuthServiceError.IncorrectCurrentPassword, "Current password is incorrect.");
}
