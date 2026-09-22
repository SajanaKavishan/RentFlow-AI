namespace RentFlow.Api.Models;

/// <summary>
/// Represents the current state of a rental offer.
/// </summary>
public enum RentalOfferStatus
{
    Pending,
    Accepted,
    Rejected,
    Withdrawn,
    Expired
}