namespace RentFlow.Api.Models;

/// <summary>
/// Represents an immutable maintenance request status transition.
/// </summary>
public class MaintenanceStatusHistory
{
    public Guid Id { get; set; } = Guid.NewGuid();

    public Guid MaintenanceRequestId { get; set; }

    public MaintenanceRequestStatus? FromStatus { get; set; }

    public MaintenanceRequestStatus ToStatus { get; set; }

    public Guid? ChangedByUserId { get; set; }

    public DateTimeOffset ChangedAt { get; set; } = DateTimeOffset.UtcNow;

    public string? Notes { get; set; }

    public MaintenanceRequest MaintenanceRequest { get; set; } = null!;
}
