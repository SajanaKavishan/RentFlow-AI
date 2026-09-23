using RentFlow.Api.Models;

namespace RentFlow.Api.DTOs.Maintenance;

/// <summary>
/// Carries the input required to create a maintenance request.
/// </summary>
public class CreateMaintenanceRequestDto
{
    public Guid PropertyId { get; set; }

    public string Title { get; set; } = string.Empty;

    public string Description { get; set; } = string.Empty;

    public MaintenanceCategory Category { get; set; }

    public MaintenancePriority Priority { get; set; }

    public string? TenantAccessNotes { get; set; }
}
