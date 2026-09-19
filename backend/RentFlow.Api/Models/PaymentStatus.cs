namespace RentFlow.Api.Models;

/// <summary>
/// Represents the processing state of a rent payment.
/// </summary>
public enum PaymentStatus
{
    Pending,
    Completed,
    Failed
}