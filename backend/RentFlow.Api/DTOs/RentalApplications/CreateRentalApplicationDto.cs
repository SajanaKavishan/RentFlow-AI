namespace RentFlow.Api.DTOs.RentalApplications;

/// <summary>
/// Carries the input required to create a rental application.
/// </summary>
public class CreateRentalApplicationDto
{
    public Guid PropertyId { get; set; }

    public DateOnly MoveInDate { get; set; }

    public decimal MonthlyIncome { get; set; }

    public string Occupation { get; set; } = string.Empty;

    public int NumberOfOccupants { get; set; }

    public string? TenantNote { get; set; }
}
