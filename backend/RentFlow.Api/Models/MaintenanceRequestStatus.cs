namespace RentFlow.Api.Models;

/// <summary>
/// Represents the current state of a maintenance request.
/// </summary>
public enum MaintenanceRequestStatus
{
    Submitted,
    Triaged,
    Assigned,
    EstimatePending,
    EstimateSubmitted,
    AwaitingLandlordApproval,
    Approved,
    Rejected,
    InProgress,
    Completed,
    Cancelled
}
