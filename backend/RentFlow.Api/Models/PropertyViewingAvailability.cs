namespace RentFlow.Api.Models;

/// <summary>One property-local window per weekday. Contract: Sunday=0 through Saturday=6.</summary>
public sealed class PropertyViewingAvailability
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid PropertyId { get; set; }
    public int DayOfWeek { get; set; }
    public TimeOnly StartTime { get; set; }
    public TimeOnly EndTime { get; set; }
    public bool IsEnabled { get; set; }
}
