namespace RentFlow.Api.Models;

/// <summary>
/// Represents the current state of a rental application.
/// </summary>
public enum RentalApplicationStatus
{
    Draft,
    Submitted,
    UnderReview,
    ChangesRequested,
    Approved,
    Rejected,
    Withdrawn
}
