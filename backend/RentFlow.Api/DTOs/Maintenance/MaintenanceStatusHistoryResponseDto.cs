using RentFlow.Api.Models;

namespace RentFlow.Api.DTOs.Maintenance;

/// <summary>
/// Represents a maintenance request status transition returned by the API.
/// </summary>
public class MaintenanceStatusHistoryResponseDto
{
    public Guid Id { get; set; }

    public MaintenanceRequestStatus? FromStatus { get; set; }

    public MaintenanceRequestStatus ToStatus { get; set; }

    public Guid? ChangedByUserId { get; set; }

    public string? ChangedByName { get; set; }

    public UserRole? ChangedByRole { get; set; }

    public DateTimeOffset ChangedAt { get; set; }

    public string? Notes { get; set; }
}
