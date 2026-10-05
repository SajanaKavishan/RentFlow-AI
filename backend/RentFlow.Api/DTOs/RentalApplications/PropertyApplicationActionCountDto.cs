namespace RentFlow.Api.DTOs.RentalApplications;

public sealed class PropertyApplicationActionCountDto
{
    public Guid PropertyId { get; set; }
    public int ActionRequiredCount { get; set; }
}
