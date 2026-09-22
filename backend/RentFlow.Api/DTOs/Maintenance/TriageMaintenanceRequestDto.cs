using RentFlow.Api.Models;

namespace RentFlow.Api.DTOs.Maintenance;

/// <summary>
/// Carries a manager's triage decision for a maintenance request.
/// </summary>
public class TriageMaintenanceRequestDto
{
    public MaintenanceCategory Category { get; set; }

    public MaintenancePriority Priority { get; set; }

    public string? TriageNotes { get; set; }
}
