namespace RentFlow.Api.DTOs.RentalApplications;

/// <summary>
/// Carries tenant-editable rental application details.
/// </summary>
public class UpdateRentalApplicationDto
{
    public DateOnly MoveInDate { get; set; }

    public decimal MonthlyIncome { get; set; }

    public string Occupation { get; set; } = string.Empty;

    public int NumberOfOccupants { get; set; }

    public string? TenantNote { get; set; }
}
