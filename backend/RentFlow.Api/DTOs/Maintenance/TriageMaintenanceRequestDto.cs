using System.Text.Json.Serialization;
using RentFlow.Api.Models;

namespace RentFlow.Api.DTOs.Maintenance;

/// <summary>
/// Carries a manager's triage decision for a maintenance request.
/// </summary>
public class TriageMaintenanceRequestDto
{
    [JsonRequired]
    public MaintenanceCategory Category { get; set; }

    [JsonRequired]
    public MaintenancePriority Priority { get; set; }

    public string? TriageNotes { get; set; }
}
