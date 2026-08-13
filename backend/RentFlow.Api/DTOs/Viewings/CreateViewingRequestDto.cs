namespace RentFlow.Api.DTOs.Viewings;

/// <summary>
/// Carries the input required to create a viewing request.
/// </summary>
public class CreateViewingRequestDto
{
    public Guid PropertyId { get; set; }

    public DateTimeOffset RequestedDateTime { get; set; }

    public string? TenantMessage { get; set; }
}
