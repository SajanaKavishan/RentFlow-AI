using Microsoft.EntityFrameworkCore;
using RentFlow.Api.Data;
using RentFlow.Api.DTOs.Viewings;
using RentFlow.Api.Models;
using RentFlow.Api.Services;
using Xunit;

namespace RentFlow.Api.Tests.Services;

public sealed class ViewingAvailabilityServiceTests
{
    internal static readonly DateOnly Date = new(2030, 10, 7);
    internal sealed class Clock(DateTimeOffset now) : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() => now;
    }
    private static readonly Clock Time = new(new DateTimeOffset(2030, 10, 6, 0, 0, 0, TimeSpan.Zero));

    internal static ViewingAvailabilityDto Schedule(Guid id, int duration = 60) => new()
    {
        PropertyId = id, SlotDurationMinutes = duration,
        Windows = [new() { DayOfWeek = (int)Date.DayOfWeek, IsEnabled = true,
            StartTime = new TimeOnly(9, 0), EndTime = new TimeOnly(17, 0) }]
    };
    internal static Property Property() => new()
    {
        LandlordId = Guid.NewGuid(), Title = "Viewing home", City = "Colombo", Address = "1 Test Road",
        Description = "Test", MonthlyRent = 100000, Bedrooms = 1, Bathrooms = 1,
        AvailableFrom = Date.AddMonths(2)
    };
    private static ApplicationDbContext Context() => new(new DbContextOptionsBuilder<ApplicationDbContext>()
        .UseInMemoryDatabase(Guid.NewGuid().ToString()).Options);

    [Fact]
    public async Task SaveAndGenerate_UsesLocalWeekdayAndUtcInstant_WithoutMoveInRestriction()
    {
        await using var db = Context(); var property = Property(); db.Add(property); await db.SaveChangesAsync();
        var service = new ViewingAvailabilityService(db, Time);
        Assert.Empty((await service.GetSlotsAsync(property.Id, Date)).Slots);
        var saved = await service.SaveAsync(property.Id, property.LandlordId, Schedule(property.Id));
        Assert.Equal("Asia/Colombo", saved.TimeZoneId);
        var result = await service.GetSlotsAsync(property.Id, Date);
        Assert.Equal(8, result.Slots.Count);
        Assert.Equal("09:00", result.Slots[0].LocalTime);
        Assert.Equal("16:00", result.Slots[^1].LocalTime);
        Assert.Equal(new DateTimeOffset(2030, 10, 7, 3, 30, 0, TimeSpan.Zero), result.Slots[0].RequestedDateTime);
        Assert.Empty((await service.GetSlotsAsync(property.Id, Date.AddDays(1))).Slots);
    }

    [Theory]
    [InlineData(0)] [InlineData(-1)] [InlineData(15)] [InlineData(120)]
    public async Task Save_RejectsInvalidDuration(int duration)
    {
        await using var db = Context(); var service = new ViewingAvailabilityService(db, Time);
        var error = await Assert.ThrowsAsync<ViewingServiceException>(() => service.SaveAsync(Guid.NewGuid(), null, Schedule(Guid.NewGuid(), duration)));
        Assert.Equal(ViewingServiceError.Validation, error.Error);
    }

    [Theory]
    [InlineData(9, 9)] [InlineData(17, 9)] [InlineData(9, 10)]
    public async Task Save_RejectsInvalidOrTooShortWindow(int start, int end)
    {
        await using var db = Context(); var input = Schedule(Guid.NewGuid(), 90);
        input.Windows[0].StartTime = new(start, 0); input.Windows[0].EndTime = new(end, 0);
        Assert.Equal(ViewingServiceError.Validation, (await Assert.ThrowsAsync<ViewingServiceException>(() =>
            new ViewingAvailabilityService(db).SaveAsync(input.PropertyId, null, input))).Error);
    }

    [Fact]
    public async Task Save_ValidatesWeekdayDuplicateTimezoneAndOwnership()
    {
        await using var db = Context(); var property = Property(); db.Add(property); await db.SaveChangesAsync();
        var service = new ViewingAvailabilityService(db, Time);
        var input = Schedule(property.Id); input.Windows[0].DayOfWeek = 7;
        await Assert.ThrowsAsync<ViewingServiceException>(() => service.SaveAsync(property.Id, null, input));
        input = Schedule(property.Id); input.Windows.Add(input.Windows[0]);
        await Assert.ThrowsAsync<ViewingServiceException>(() => service.SaveAsync(property.Id, null, input));
        input = Schedule(property.Id); input.TimeZoneId = "Invalid/Zone";
        await Assert.ThrowsAsync<ViewingServiceException>(() => service.SaveAsync(property.Id, null, input));
        Assert.Equal(ViewingServiceError.NotFound, (await Assert.ThrowsAsync<ViewingServiceException>(() =>
            service.SaveAsync(property.Id, Guid.NewGuid(), Schedule(property.Id)))).Error);
        Assert.Empty(db.PropertyViewingAvailabilities);
    }

    [Fact]
    public async Task DisabledDay_ClearsTimes_AndIncompleteRemainderIsOmitted()
    {
        await using var db = Context(); var property = Property(); db.Add(property); await db.SaveChangesAsync();
        var service = new ViewingAvailabilityService(db, Time); var input = Schedule(property.Id, 90);
        await service.SaveAsync(property.Id, property.LandlordId, input);
        Assert.Equal(5, (await service.GetSlotsAsync(property.Id, Date)).Slots.Count);
        input.Windows[0].IsEnabled = false; input.Windows[0].StartTime = null; input.Windows[0].EndTime = null;
        await service.SaveAsync(property.Id, property.LandlordId, input);
        Assert.Empty((await service.GetSlotsAsync(property.Id, Date)).Slots);
    }

    [Theory]
    [InlineData(ViewingStatus.Pending, 8)] [InlineData(ViewingStatus.Rejected, 8)]
    [InlineData(ViewingStatus.Cancelled, 8)] [InlineData(ViewingStatus.Completed, 8)]
    [InlineData(ViewingStatus.Approved, 6)]
    public async Task OnlyApprovedIntervalsBlock_AdjacentBoundaryRemainsAvailable(ViewingStatus status, int count)
    {
        await using var db = Context(); var property = Property(); db.Add(property); await db.SaveChangesAsync();
        var service = new ViewingAvailabilityService(db, Time);
        await service.SaveAsync(property.Id, property.LandlordId, Schedule(property.Id));
        db.Add(new ViewingRequest { PropertyId = property.Id, TenantId = Guid.NewGuid(), Status = status,
            RequestedDateTime = new(2030, 10, 7, 4, 0, 0, TimeSpan.Zero), DurationMinutes = 90 });
        await db.SaveChangesAsync();
        var result = await service.GetSlotsAsync(property.Id, Date);
        Assert.Equal(count, result.Slots.Count);
        Assert.Contains(result.Slots, slot => slot.LocalTime == "11:00");
        Assert.All(result.Slots, slot => Assert.True(slot.IsAvailable));
        var enriched = await service.GetSlotsAsync(property.Id, Date, includeUnavailable: true);
        Assert.Equal(8, enriched.Slots.Count);
        Assert.Equal(8 - count, enriched.Slots.Count(slot => !slot.IsAvailable));
        Assert.All(enriched.Slots.Where(slot => !slot.IsAvailable),
            slot => Assert.Equal("ApprovedViewing", slot.UnavailableReason));
        Assert.All(enriched.Slots.Where(slot => slot.IsAvailable), slot => Assert.Null(slot.UnavailableReason));
        Assert.True(enriched.Slots.Single(slot => slot.LocalTime == "11:00").IsAvailable);
    }

    [Fact]
    public async Task SameDay_ElapsedSlotsOmitted()
    {
        await using var db = Context(); var property = Property(); db.Add(property); await db.SaveChangesAsync();
        var service = new ViewingAvailabilityService(db, new Clock(new(2030, 10, 7, 3, 45, 0, TimeSpan.Zero)));
        await service.SaveAsync(property.Id, property.LandlordId, Schedule(property.Id));
        Assert.Equal("10:00", (await service.GetSlotsAsync(property.Id, Date)).Slots[0].LocalTime);
    }

    [Fact]
    public async Task PastCalendarDatesReturnEmptyWithoutUtcBoundaryOverflow()
    {
        await using var db = Context(); var property = Property(); db.Add(property); await db.SaveChangesAsync();
        var service = new ViewingAvailabilityService(db, Time);
        var input = Schedule(property.Id); input.Windows[0].DayOfWeek = (int)DateOnly.MinValue.DayOfWeek;
        input.Windows[0].StartTime = TimeOnly.MinValue;
        await service.SaveAsync(property.Id, property.LandlordId, input);
        var result = await service.GetSlotsAsync(property.Id, DateOnly.MinValue);
        Assert.Empty(result.Slots); Assert.Equal("past", result.State);
        await Assert.ThrowsAsync<ViewingServiceException>(() => service.GetSlotsAsync(property.Id, DateOnly.MaxValue));
    }

    [Fact]
    public async Task Create_RevalidatesSlotsEligibilityDuplicatesAndDuration_ApproveRechecksOverlaps()
    {
        await using var db = Context(); var property = Property(); db.Add(property); await db.SaveChangesAsync();
        var schedule = new ViewingAvailabilityService(db, Time);
        await schedule.SaveAsync(property.Id, property.LandlordId, Schedule(property.Id));
        var slots = await schedule.GetSlotsAsync(property.Id, Date);
        var service = new ViewingService(db, Time);
        var input = new CreateViewingRequestDto { TenantMessage = "Please arrange a visit.", PropertyId = property.Id, RequestedDateTime = slots.Slots[0].RequestedDateTime };
        var first = await service.CreateAsync(Guid.NewGuid(), input);
        var second = await service.CreateAsync(Guid.NewGuid(), input);
        Assert.Equal(ViewingStatus.Pending, first.Status); Assert.Equal(60, first.DurationMinutes);
        await Assert.ThrowsAsync<ViewingServiceException>(() => service.CreateAsync(first.TenantId, input));
        await service.ApproveAsync(first.Id);
        Assert.Equal(ViewingServiceError.Conflict, (await Assert.ThrowsAsync<ViewingServiceException>(() => service.ApproveAsync(second.Id))).Error);
        Assert.Equal(ViewingStatus.Pending, (await service.GetByIdAsync(second.Id))!.Status);
        await Assert.ThrowsAsync<ViewingServiceException>(() => service.CreateAsync(Guid.NewGuid(), input));
        input.RequestedDateTime = slots.Slots[2].RequestedDateTime.AddMinutes(1);
        await Assert.ThrowsAsync<ViewingServiceException>(() => service.CreateAsync(Guid.NewGuid(), input));
        input.RequestedDateTime = slots.Slots[2].RequestedDateTime;
        property.IsAvailable = false; await db.SaveChangesAsync();
        await Assert.ThrowsAsync<ViewingServiceException>(() => service.CreateAsync(Guid.NewGuid(), input));
        property.IsAvailable = true; await db.SaveChangesAsync();
        var changed = Schedule(property.Id, 30); await schedule.SaveAsync(property.Id, property.LandlordId, changed);
        var next = await service.CreateAsync(Guid.NewGuid(), input);
        Assert.Equal(30, next.DurationMinutes); Assert.Equal(60, (await service.GetByIdAsync(first.Id))!.DurationMinutes);
        await service.CancelAsync(first.Id, first.TenantId);
        await Assert.ThrowsAsync<ViewingServiceException>(() => service.CreateAsync(first.TenantId,
            new() { TenantMessage = "Please arrange a visit.", PropertyId = property.Id, RequestedDateTime = slots.Slots[0].RequestedDateTime }));
    }

    [Fact]
    public async Task ApprovalRejectsElapsedRequest_AndLongTenantNoteIsValidationError()
    {
        await using var db = Context(); var property = Property(); db.Add(property);
        var viewing = new ViewingRequest { PropertyId = property.Id, RequestedDateTime = Time.GetUtcNow().AddMinutes(-1) };
        db.Add(viewing); await db.SaveChangesAsync(); var service = new ViewingService(db, Time);
        await Assert.ThrowsAsync<ViewingServiceException>(() => service.ApproveAsync(viewing.Id));
        Assert.Equal(ViewingServiceError.Validation, (await Assert.ThrowsAsync<ViewingServiceException>(() =>
            service.CreateAsync(Guid.NewGuid(), new() { PropertyId = property.Id, RequestedDateTime = Time.GetUtcNow().AddDays(1), TenantMessage = new string('a', 501) }))).Error);
    }
}
