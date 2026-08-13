namespace RentFlow.Api.Models;

/// <summary>
/// Represents a tenant's request to view a property.
/// </summary>
public class ViewingRequest
{
    public Guid Id { get; set; } = Guid.NewGuid();

    public Guid TenantId { get; set; }

    public Guid PropertyId { get; set; }

    public DateTimeOffset RequestedDateTime { get; set; }

    public ViewingStatus Status { get; set; } = ViewingStatus.Pending;

    public string? TenantMessage { get; set; }

    public string? LandlordResponse { get; set; }

    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;

    public DateTimeOffset? UpdatedAt { get; set; }
}
