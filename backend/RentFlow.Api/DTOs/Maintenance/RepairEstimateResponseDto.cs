using RentFlow.Api.Models;

namespace RentFlow.Api.DTOs.Maintenance;

/// <summary>
/// Represents a repair estimate returned by the API.
/// </summary>
public class RepairEstimateResponseDto
{
    public Guid Id { get; set; }

    public Guid MaintenanceRequestId { get; set; }

    public Guid TechnicianId { get; set; }

    public int VersionNumber { get; set; }

    public decimal LaborCost { get; set; }

    public decimal PartsCost { get; set; }

    public decimal AdditionalCost { get; set; }

    public decimal TotalCost { get; set; }

    public string? Notes { get; set; }

    public RepairEstimateStatus Status { get; set; }

    public DateTimeOffset CreatedAt { get; set; }

    public DateTimeOffset? SubmittedAt { get; set; }

    public DateTimeOffset? ReviewedAt { get; set; }

    public string? ReviewNotes { get; set; }
}
