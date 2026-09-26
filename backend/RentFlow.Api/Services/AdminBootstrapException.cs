namespace RentFlow.Api.Services;

public enum AdminBootstrapError
{
    Validation,
    DuplicateEmail,
    AlreadyCompleted
}

public sealed class AdminBootstrapException(
    AdminBootstrapError error,
    string message) : Exception(message)
{
    public AdminBootstrapError Error { get; } = error;

    public static AdminBootstrapException Validation(string message) =>
        new(AdminBootstrapError.Validation, message);

    public static AdminBootstrapException DuplicateEmail() =>
        new(
            AdminBootstrapError.DuplicateEmail,
            "An account with this email already exists.");

    public static AdminBootstrapException AlreadyCompleted() =>
        new(
            AdminBootstrapError.AlreadyCompleted,
            "Initial Admin provisioning has already been completed or an Admin account already exists.");
}
