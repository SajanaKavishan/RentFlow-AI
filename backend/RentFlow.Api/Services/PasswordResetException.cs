namespace RentFlow.Api.Services;

public enum PasswordResetError
{
    Validation,
    InvalidOrExpiredToken,
    Persistence
}

public sealed class PasswordResetException(
    PasswordResetError error,
    string message) : Exception(message)
{
    public PasswordResetError Error { get; } = error;

    public static PasswordResetException Validation(string message) =>
        new(PasswordResetError.Validation, message);

    public static PasswordResetException InvalidOrExpiredToken() =>
        new(
            PasswordResetError.InvalidOrExpiredToken,
            "The password reset token is invalid, expired, or has already been used.");

    public static PasswordResetException Persistence() =>
        new(
            PasswordResetError.Persistence,
            "The password reset request could not be completed.");
}
