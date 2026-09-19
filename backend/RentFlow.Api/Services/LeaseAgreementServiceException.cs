namespace RentFlow.Api.Services;

public enum LeaseAgreementServiceError
{
    Validation,
    NotFound,
    Conflict
}

public sealed class LeaseAgreementServiceException : Exception
{
    private LeaseAgreementServiceException(
        LeaseAgreementServiceError error,
        string message)
        : base(message)
    {
        Error = error;
    }

    public LeaseAgreementServiceError Error { get; }

    public static LeaseAgreementServiceException Validation(string message) =>
        new(LeaseAgreementServiceError.Validation, message);

    public static LeaseAgreementServiceException NotFound(string message) =>
        new(LeaseAgreementServiceError.NotFound, message);

    public static LeaseAgreementServiceException Conflict(string message) =>
        new(LeaseAgreementServiceError.Conflict, message);
}