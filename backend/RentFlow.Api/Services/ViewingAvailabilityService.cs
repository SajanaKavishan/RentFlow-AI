using System.Globalization;
using Microsoft.EntityFrameworkCore;
using RentFlow.Api.Data;
using RentFlow.Api.DTOs.Viewings;
using RentFlow.Api.Models;

namespace RentFlow.Api.Services;

public sealed class ViewingAvailabilityService(ApplicationDbContext context, TimeProvider? timeProvider = null)
{
    private DateTimeOffset Now => (timeProvider ?? TimeProvider.System).GetUtcNow();
    public static readonly int[] SupportedDurations = [30, 45, 60, 90];

    public async Task<Property> GetPropertyAsync(Guid id, CancellationToken ct = default) =>
        await context.Properties.AsNoTracking().SingleOrDefaultAsync(p => p.Id == id, ct)
        ?? throw ViewingServiceException.NotFound("The property was not found.");

    public async Task<ViewingAvailabilityDto> GetAsync(Guid id, CancellationToken ct = default)
    {
        var property = await GetPropertyAsync(id, ct);
        var windows = await context.PropertyViewingAvailabilities.AsNoTracking()
            .Where(w => w.PropertyId == id).OrderBy(w => w.DayOfWeek).ToListAsync(ct);
        return new ViewingAvailabilityDto
        {
            PropertyId = id, TimeZoneId = property.ViewingTimeZoneId,
            SlotDurationMinutes = property.ViewingSlotDurationMinutes,
            Windows = windows.Select(w => new ViewingWindowDto
            {
                DayOfWeek = w.DayOfWeek, IsEnabled = w.IsEnabled,
                StartTime = w.IsEnabled ? w.StartTime : null,
                EndTime = w.IsEnabled ? w.EndTime : null
            }).ToList()
        };
    }

    public async Task<ViewingAvailabilityDto> SaveAsync(Guid id, Guid? ownerId,
        ViewingAvailabilityDto input, CancellationToken ct = default)
    {
        Validate(input);
        await using var transaction = await ViewingPropertyLock.AcquireAsync(context, id, ct);
        var property = await context.Properties.SingleOrDefaultAsync(p => p.Id == id, ct)
            ?? throw ViewingServiceException.NotFound("The property was not found.");
        await context.Entry(property).ReloadAsync(ct);
        if (ownerId.HasValue && property.LandlordId != ownerId.Value)
            throw ViewingServiceException.NotFound("The property was not found.");
        property.ViewingSlotDurationMinutes = input.SlotDurationMinutes;
        property.ViewingTimeZoneId = input.TimeZoneId;
        var existing = await context.PropertyViewingAvailabilities.Where(w => w.PropertyId == id).ToListAsync(ct);
        foreach (var row in existing) await context.Entry(row).ReloadAsync(ct);
        foreach (var row in existing.Where(w => input.Windows.All(i => i.DayOfWeek != w.DayOfWeek)))
            context.PropertyViewingAvailabilities.Remove(row);
        foreach (var window in input.Windows)
        {
            var row = existing.SingleOrDefault(w => w.DayOfWeek == window.DayOfWeek);
            if (row is null)
            {
                row = new PropertyViewingAvailability { PropertyId = id, DayOfWeek = window.DayOfWeek };
                context.PropertyViewingAvailabilities.Add(row);
            }
            row.IsEnabled = window.IsEnabled;
            row.StartTime = window.IsEnabled ? window.StartTime!.Value : TimeOnly.MinValue;
            row.EndTime = window.IsEnabled ? window.EndTime!.Value : TimeOnly.MinValue;
        }
        await context.SaveChangesAsync(ct);
        if (transaction is not null) await transaction.CommitAsync(ct);
        return await GetAsync(id, ct);
    }

    private static void Validate(ViewingAvailabilityDto input)
    {
        if (!SupportedDurations.Contains(input.SlotDurationMinutes))
            throw ViewingServiceException.Validation("Slot duration must be 30, 45, 60, or 90 minutes.");
        ResolveZone(input.TimeZoneId);
        if (input.Windows is null || input.Windows.Count > 7
            || input.Windows.Any(w => w is null || w.DayOfWeek is < 0 or > 6)
            || input.Windows.Select(w => w.DayOfWeek).Distinct().Count() != input.Windows.Count)
            throw ViewingServiceException.Validation("Provide at most one window per weekday (Sunday=0 through Saturday=6).");
        foreach (var window in input.Windows.Where(w => w.IsEnabled))
        {
            if (window.StartTime is null || window.EndTime is null || window.StartTime >= window.EndTime)
                throw ViewingServiceException.Validation("Enabled days require a start time before the end time; overnight windows are not supported.");
            if (window.StartTime.Value.Second != 0 || window.EndTime.Value.Second != 0
                || window.StartTime.Value.Ticks % TimeSpan.TicksPerMinute != 0
                || window.EndTime.Value.Ticks % TimeSpan.TicksPerMinute != 0)
                throw ViewingServiceException.Validation("Window times must use whole minutes.");
            if ((window.EndTime.Value - window.StartTime.Value).TotalMinutes < input.SlotDurationMinutes)
                throw ViewingServiceException.Validation("The slot duration must fit inside every enabled window.");
        }
    }

    public static TimeZoneInfo ResolveZone(string id)
    {
        // IANA identifiers form the portable API contract, not Windows timezone names.
        if (string.IsNullOrWhiteSpace(id) || (id != "UTC" && !id.Contains('/')))
            throw ViewingServiceException.Validation("A valid IANA timezone ID is required.");
        try { return TimeZoneInfo.FindSystemTimeZoneById(id); }
        catch (TimeZoneNotFoundException) { throw ViewingServiceException.Validation("The scheduling timezone is unsupported."); }
        catch (InvalidTimeZoneException) { throw ViewingServiceException.Validation("The scheduling timezone is invalid."); }
    }

    public async Task<ViewingSlotsDto> GetSlotsAsync(Guid id, DateOnly date, CancellationToken ct = default)
    {
        var property = await GetPropertyAsync(id, ct);
        if (!property.IsAvailable) throw ViewingServiceException.Conflict("This property is not accepting viewing requests.");
        var schedule = await GetAsync(id, ct);
        var zone = ResolveZone(schedule.TimeZoneId);
        if (date == DateOnly.MaxValue)
            throw ViewingServiceException.Validation("The selected calendar date is outside the supported scheduling range.");
        if (date < DateOnly.FromDateTime(TimeZoneInfo.ConvertTime(Now, zone).DateTime))
            return new(date, schedule.TimeZoneId, schedule.SlotDurationMinutes, [], "past");
        var window = schedule.Windows.SingleOrDefault(w => w.DayOfWeek == (int)date.DayOfWeek && w.IsEnabled);
        var slots = new List<ViewingSlotDto>();
        if (window is null)
            return new(date, schedule.TimeZoneId, schedule.SlotDurationMinutes, slots,
                schedule.Windows.Count == 0 ? "unconfigured" : "disabled");

        var start = date.ToDateTime(window.StartTime!.Value, DateTimeKind.Unspecified);
        var end = date.ToDateTime(window.EndTime!.Value, DateTimeKind.Unspecified);
        // Filter by interval below, including appointments starting before this date/window.
        var approved = await context.ViewingRequests.AsNoTracking()
            .Where(v => v.PropertyId == id && v.Status == ViewingStatus.Approved).ToListAsync(ct);
        for (var local = start; local.AddMinutes(schedule.SlotDurationMinutes) <= end;
             local = local.AddMinutes(schedule.SlotDurationMinutes))
        {
            var localEnd = local.AddMinutes(schedule.SlotDurationMinutes);
            // No invented interpretation of DST gaps/folds: omit ambiguous/invalid slots.
            if (zone.IsInvalidTime(local) || zone.IsAmbiguousTime(local)
                || zone.IsInvalidTime(localEnd) || zone.IsAmbiguousTime(localEnd)) continue;
            var instant = new DateTimeOffset(TimeZoneInfo.ConvertTimeToUtc(local, zone));
            var finish = new DateTimeOffset(TimeZoneInfo.ConvertTimeToUtc(localEnd, zone));
            if (instant <= Now || finish - instant != TimeSpan.FromMinutes(schedule.SlotDurationMinutes)) continue;
            if (approved.Any(v => Overlaps(v, instant, finish))) continue;
            slots.Add(new(local.ToString("HH:mm", CultureInfo.InvariantCulture),
                local.ToString("h:mm tt", CultureInfo.InvariantCulture), instant));
        }
        return new(date, schedule.TimeZoneId, schedule.SlotDurationMinutes, slots, slots.Count == 0 ? "empty" : "available");
    }

    public async Task<bool> HasApprovedOverlapAsync(Guid id, DateTimeOffset start, int duration,
        Guid? exclude = null, CancellationToken ct = default)
    {
        var end = start.AddMinutes(duration);
        var approved = await context.ViewingRequests.AsNoTracking()
            .Where(v => v.PropertyId == id && v.Status == ViewingStatus.Approved
                && v.Id != exclude && v.RequestedDateTime < end).ToListAsync(ct);
        return approved.Any(v => Overlaps(v, start, end));
    }

    private static bool Overlaps(ViewingRequest viewing, DateTimeOffset start, DateTimeOffset end)
    {
        if (viewing.DurationMinutes is not > 0)
            throw ViewingServiceException.Conflict("An approved legacy viewing has no duration. Its duration must be resolved before scheduling.");
        return viewing.RequestedDateTime < end && viewing.RequestedDateTime.AddMinutes(viewing.DurationMinutes) > start;
    }
}
