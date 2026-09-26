namespace RentFlow.Api.Services;

public enum TechnicianProvisioningError
{
    Validation,
    DuplicateEmail,
    InvalidOrExpiredToken,
    Forbidden,
    Persistence
}

public sealed class TechnicianProvisioningException(
    TechnicianProvisioningError error,
    string message) : Exception(message)
{
    public TechnicianProvisioningError Error { get; } = error;

    public static TechnicianProvisioningException Validation(string message) =>
        new(TechnicianProvisioningError.Validation, message);

    public static TechnicianProvisioningException DuplicateEmail() =>
        new(
            TechnicianProvisioningError.DuplicateEmail,
            "An account with this email already exists.");

    public static TechnicianProvisioningException InvalidOrExpiredToken() =>
        new(
            TechnicianProvisioningError.InvalidOrExpiredToken,
            "The password setup token is invalid, expired, or has already been used.");

    public static TechnicianProvisioningException Forbidden() =>
        new(
            TechnicianProvisioningError.Forbidden,
            "An active Admin account is required.");

    public static TechnicianProvisioningException Persistence() =>
        new(
            TechnicianProvisioningError.Persistence,
            "The staff provisioning request could not be completed.");
}
