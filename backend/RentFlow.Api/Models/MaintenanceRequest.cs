namespace RentFlow.Api.Models;

/// <summary>
/// Represents a tenant's maintenance request for a property.
/// </summary>
public class MaintenanceRequest
{
    public Guid Id { get; set; } = Guid.NewGuid();

    public string ReferenceCode { get; set; } = string.Empty;

    public PreferredAccessWindow? PreferredAccessWindow { get; set; }

    public Guid PropertyId { get; set; }

    public Guid TenantId { get; set; }

    public Guid? TechnicianId { get; set; }

    public string Title { get; set; } = string.Empty;

    public string Description { get; set; } = string.Empty;

    public MaintenanceCategory Category { get; set; }

    public MaintenancePriority Priority { get; set; } = MaintenancePriority.Normal;

    public MaintenanceRequestStatus Status { get; set; } = MaintenanceRequestStatus.Submitted;

    public string? TenantAccessNotes { get; set; }

    public string? TriageNotes { get; set; }

    public string? AssignmentNotes { get; set; }

    public string? CancellationReason { get; set; }

    public DateTimeOffset? CompletedAt { get; set; }

    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;

    public DateTimeOffset? UpdatedAt { get; set; }
}
