namespace RentFlow.Api.DTOs.Viewings;

public sealed class ViewingWindowDto
{
    // Sunday=0, Monday=1, Tuesday=2, Wednesday=3, Thursday=4, Friday=5, Saturday=6.
    public int DayOfWeek { get; set; }
    public bool IsEnabled { get; set; }
    public TimeOnly? StartTime { get; set; }
    public TimeOnly? EndTime { get; set; }
}

public sealed class ViewingAvailabilityDto
{
    public Guid PropertyId { get; set; }
    public string TimeZoneId { get; set; } = "Asia/Colombo";
    public int SlotDurationMinutes { get; set; } = 60;
    public List<ViewingWindowDto> Windows { get; set; } = [];
}

public sealed record ViewingSlotDto(string LocalTime, string DisplayTime, DateTimeOffset RequestedDateTime,
    bool IsAvailable = true, string? UnavailableReason = null);
public sealed record ViewingSlotsDto(DateOnly Date, string TimeZoneId, int SlotDurationMinutes,
    IReadOnlyList<ViewingSlotDto> Slots, string State);

public sealed record ViewingDatesDto(Guid PropertyId, string TimeZoneId, DateOnly FirstDate,
    DateOnly LastDate, IReadOnlyList<DateOnly> AvailableDates, string State);
