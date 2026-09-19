namespace RentFlow.Api.Services;

public enum PaymentServiceError
{
    Validation,
    NotFound,
    Conflict
}

public sealed class PaymentServiceException : Exception
{
    private PaymentServiceException(
        PaymentServiceError error,
        string message)
        : base(message)
    {
        Error = error;
    }

    public PaymentServiceError Error { get; }

    public static PaymentServiceException Validation(string message) =>
        new(PaymentServiceError.Validation, message);

    public static PaymentServiceException NotFound(string message) =>
        new(PaymentServiceError.NotFound, message);

    public static PaymentServiceException Conflict(string message) =>
        new(PaymentServiceError.Conflict, message);
}