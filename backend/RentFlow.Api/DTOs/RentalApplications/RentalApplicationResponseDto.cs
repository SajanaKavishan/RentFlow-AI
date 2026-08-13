using RentFlow.Api.Models;

namespace RentFlow.Api.DTOs.RentalApplications;

/// <summary>
/// Represents rental application data returned by the API.
/// </summary>
public class RentalApplicationResponseDto
{
    public Guid Id { get; set; }

    public Guid TenantId { get; set; }

    public Guid PropertyId { get; set; }

    public DateOnly MoveInDate { get; set; }

    public decimal MonthlyIncome { get; set; }

    public string Occupation { get; set; } = string.Empty;

    public int NumberOfOccupants { get; set; }

    public string? TenantNote { get; set; }

    public RentalApplicationStatus Status { get; set; }

    public string? LandlordResponse { get; set; }

    public DateTimeOffset CreatedAt { get; set; }

    public DateTimeOffset? SubmittedAt { get; set; }

    public DateTimeOffset? UpdatedAt { get; set; }
}
