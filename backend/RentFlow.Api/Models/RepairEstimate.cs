namespace RentFlow.Api.Models;

/// <summary>
/// Represents a technician's repair-cost estimate for a maintenance request.
/// </summary>
public class RepairEstimate
{
    public Guid Id { get; set; } = Guid.NewGuid();

    public Guid MaintenanceRequestId { get; set; }

    public Guid TechnicianId { get; set; }

    public int VersionNumber { get; set; }

    public decimal LaborCost { get; set; }

    public decimal PartsCost { get; set; }

    public decimal AdditionalCost { get; set; }

    public decimal TotalCost { get; set; }

    public string? Notes { get; set; }

    public RepairEstimateStatus Status { get; set; }

    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;

    public DateTimeOffset? UpdatedAt { get; set; }

    public DateTimeOffset? SubmittedAt { get; set; }

    public DateTimeOffset? ReviewedAt { get; set; }

    public string? ReviewNotes { get; set; }

    public Guid? ReviewedByUserId { get; set; }

    public MaintenanceRequest MaintenanceRequest { get; set; } = null!;
}
