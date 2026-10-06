namespace RentFlow.Api.DTOs.Viewings;

public sealed class PropertyPendingViewingCountDto
{
    public Guid PropertyId { get; set; }
    public int PendingCount { get; set; }
}
