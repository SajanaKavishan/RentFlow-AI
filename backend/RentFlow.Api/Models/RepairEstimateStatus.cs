namespace RentFlow.Api.Models;

/// <summary>
/// Represents the review state of a repair estimate.
/// </summary>
public enum RepairEstimateStatus
{
    Draft,
    Submitted,
    RevisionRequested,
    Approved,
    Rejected,
    Superseded
}
