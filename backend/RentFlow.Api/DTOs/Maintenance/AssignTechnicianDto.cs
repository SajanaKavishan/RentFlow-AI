namespace RentFlow.Api.DTOs.Maintenance;

/// <summary>
/// Carries the technician assignment for a maintenance request.
/// </summary>
public class AssignTechnicianDto
{
    public Guid TechnicianId { get; set; }

    public string? AssignmentNotes { get; set; }
}
