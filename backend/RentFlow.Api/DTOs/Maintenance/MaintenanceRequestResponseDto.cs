using RentFlow.Api.Models;

namespace RentFlow.Api.DTOs.Maintenance;

/// <summary>
/// Represents maintenance request data returned by the API.
/// </summary>
public class MaintenanceRequestResponseDto
{
    public Guid Id { get; set; }

    public string ReferenceCode { get; set; } = string.Empty;

    public PreferredAccessWindow? PreferredAccessWindow { get; set; }

    public Guid PropertyId { get; set; }

    public string? PropertyTitle { get; set; }

    public Guid TenantId { get; set; }

    public string? TenantName { get; set; }

    public Guid? TechnicianId { get; set; }

    public string? AssignedTechnicianName { get; set; }
    public string? AssignedTechnicianContactPhone { get; set; }

    public string Title { get; set; } = string.Empty;

    public string Description { get; set; } = string.Empty;

    public MaintenanceCategory Category { get; set; }

    public MaintenancePriority Priority { get; set; }

    public MaintenanceRequestStatus Status { get; set; }

    public string? TenantAccessNotes { get; set; }

    public string? TriageNotes { get; set; }

    public string? AssignmentNotes { get; set; }

    public string? CancellationReason { get; set; }

    public DateTimeOffset? CompletedAt { get; set; }

    public DateTimeOffset CreatedAt { get; set; }

    public DateTimeOffset? UpdatedAt { get; set; }
}
