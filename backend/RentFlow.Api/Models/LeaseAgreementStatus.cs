namespace RentFlow.Api.Models;

/// <summary>
/// Represents the current state of a lease agreement.
/// </summary>
public enum LeaseAgreementStatus
{
    Pending,
    Active,
    Terminated,
    Completed
}