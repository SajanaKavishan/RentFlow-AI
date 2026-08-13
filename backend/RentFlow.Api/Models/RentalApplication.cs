namespace RentFlow.Api.Models;

/// <summary>
/// Represents a tenant's application to rent a property.
/// </summary>
public class RentalApplication
{
    public Guid Id { get; set; } = Guid.NewGuid();

    public Guid TenantId { get; set; }

    public Guid PropertyId { get; set; }

    public DateOnly MoveInDate { get; set; }

    public decimal MonthlyIncome { get; set; }

    public string Occupation { get; set; } = string.Empty;

    public int NumberOfOccupants { get; set; }

    public string? TenantNote { get; set; }

    public RentalApplicationStatus Status { get; set; } = RentalApplicationStatus.Draft;

    public string? LandlordResponse { get; set; }

    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;

    public DateTimeOffset? SubmittedAt { get; set; }

    public DateTimeOffset? UpdatedAt { get; set; }
}
