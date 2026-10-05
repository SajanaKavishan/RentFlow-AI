using RentFlow.Api.Models;

namespace RentFlow.Api.DTOs.Maintenance;

/// <summary>
/// Represents maintenance request data for list and dashboard views.
/// </summary>
public class MaintenanceRequestSummaryDto
{
    public Guid Id { get; set; }

    public string ReferenceCode { get; set; } = string.Empty;

    public PreferredAccessWindow? PreferredAccessWindow { get; set; }

    public Guid PropertyId { get; set; }

    public Guid TenantId { get; set; }

    public Guid? TechnicianId { get; set; }

    public string Title { get; set; } = string.Empty;

    public MaintenanceCategory Category { get; set; }

    public MaintenancePriority Priority { get; set; }

    public MaintenanceRequestStatus Status { get; set; }

    public DateTimeOffset CreatedAt { get; set; }

    public DateTimeOffset? UpdatedAt { get; set; }
}
