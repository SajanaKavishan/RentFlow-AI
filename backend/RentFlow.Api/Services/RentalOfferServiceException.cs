namespace RentFlow.Api.Services;

public enum RentalOfferServiceError
{
    Validation,
    NotFound,
    Conflict
}

public sealed class RentalOfferServiceException : Exception
{
    private RentalOfferServiceException(
        RentalOfferServiceError error,
        string message)
        : base(message)
    {
        Error = error;
    }

    public RentalOfferServiceError Error { get; }

    public static RentalOfferServiceException Validation(string message) =>
        new(RentalOfferServiceError.Validation, message);

    public static RentalOfferServiceException NotFound(string message) =>
        new(RentalOfferServiceError.NotFound, message);

    public static RentalOfferServiceException Conflict(string message) =>
        new(RentalOfferServiceError.Conflict, message);
}