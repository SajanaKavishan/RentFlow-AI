using RentFlow.Api.Models;

namespace RentFlow.Api.DTOs.Maintenance;

/// <summary>
/// Carries tenant-editable maintenance request details.
/// </summary>
public class UpdateMaintenanceRequestDto
{
    public string Title { get; set; } = string.Empty;

    public string Description { get; set; } = string.Empty;

    public MaintenanceCategory Category { get; set; }

    public MaintenancePriority Priority { get; set; }

    public string? TenantAccessNotes { get; set; }
}
