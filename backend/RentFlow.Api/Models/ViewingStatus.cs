namespace RentFlow.Api.Models;

/// <summary>
/// Represents the current state of a viewing request.
/// </summary>
public enum ViewingStatus
{
    Pending,
    Approved,
    Rejected,
    Cancelled,
    Completed
}
