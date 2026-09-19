namespace RentFlow.Api.Models;

/// <summary>
/// Represents the payment state of a scheduled rent item.
/// </summary>
public enum RentScheduleStatus
{
    Pending,
    Paid,
    Overdue
}