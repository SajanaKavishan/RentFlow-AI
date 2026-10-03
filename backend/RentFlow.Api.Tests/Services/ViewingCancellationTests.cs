using Microsoft.EntityFrameworkCore;
using RentFlow.Api.Data;
using RentFlow.Api.Models;
using RentFlow.Api.Services;
using Xunit;

namespace RentFlow.Api.Tests.Services;

public sealed class ViewingCancellationTests
{
    internal sealed class Clock(DateTimeOffset now) : TimeProvider
    {
        public DateTimeOffset Now { get; set; } = now;
        public override DateTimeOffset GetUtcNow() => Now;
    }

    private static readonly DateTimeOffset Start = new(2030, 1, 2, 4, 30, 0, TimeSpan.Zero);

    [Theory]
    [InlineData(-3600, true)] // More than five hours.
    [InlineData(0, true)] // Exactly five hours.
    [InlineData(1, false)] // 4h59m59s remaining.
    [InlineData(18000, false)] // Viewing start.
    [InlineData(18001, false)] // After viewing.
    public async Task Approved_UsesServerDeadline_ForDetailListAndCancellation(int secondsAfterDeadline, bool allowed)
    {
        await using var db = Context();
        var viewing = await Seed(db, ViewingStatus.Approved);
        var deadline = Start.AddHours(-5);
        var clock = new Clock(deadline.AddSeconds(secondsAfterDeadline));
        var service = new ViewingService(db, clock);

        var detail = await service.GetByIdForTenantAsync(viewing.Id, viewing.TenantId);
        Assert.Equal(allowed, detail!.CanCancel);
        Assert.Equal(deadline, detail.CancellationDeadline);
        var list = Assert.Single(await service.GetByTenantAsync(viewing.TenantId));
        Assert.Equal(detail.CanCancel, list.CanCancel);
        Assert.Equal(detail.CancellationDeadline, list.CancellationDeadline);

        if (allowed)
        {
            var result = await service.CancelAsync(viewing.Id, viewing.TenantId);
            Assert.Equal(ViewingStatus.Cancelled, result.Status);
            Assert.False(result.CanCancel);
            Assert.Null(result.CancellationDeadline);
            Assert.Equal(clock.Now, result.UpdatedAt);
        }
        else
        {
            var error = await Assert.ThrowsAsync<ViewingServiceException>(() => service.CancelAsync(viewing.Id, viewing.TenantId));
            Assert.Equal(ViewingServiceError.Conflict, error.Error);
            Assert.Contains("cancellation window has closed", error.Message);
            Assert.Equal(ViewingStatus.Approved, (await service.GetByIdAsync(viewing.Id))!.Status);
            Assert.Null(viewing.UpdatedAt);
        }
    }

    [Theory]
    [InlineData(330)]
    [InlineData(-420)]
    [InlineData(0)]
    public async Task Approved_OneTickAfterBoundaryIsRejected_IndependentOfOffset(int offsetMinutes)
    {
        await using var db = Context();
        var viewing = await Seed(db, ViewingStatus.Approved);
        viewing.RequestedDateTime = Start.ToOffset(TimeSpan.FromMinutes(offsetMinutes));
        await db.SaveChangesAsync();
        var clock = new Clock(Start.AddHours(-5));
        var service = new ViewingService(db, clock);
        Assert.True((await service.GetByIdAsync(viewing.Id))!.CanCancel);
        clock.Now = clock.Now.AddTicks(1);
        Assert.False((await service.GetByIdAsync(viewing.Id))!.CanCancel);
        var error = await Assert.ThrowsAsync<ViewingServiceException>(() => service.CancelAsync(viewing.Id, viewing.TenantId));
        Assert.Equal(ViewingServiceError.Conflict, error.Error);
    }

    [Theory]
    [InlineData(-1, true)] // Pending remains cancellable until start.
    [InlineData(0, false)]
    [InlineData(1, false)]
    public async Task Pending_PreservesExistingFuturePolicy(int secondsAfterStart, bool allowed)
    {
        await using var db = Context();
        var viewing = await Seed(db, ViewingStatus.Pending);
        var service = new ViewingService(db, new Clock(Start.AddSeconds(secondsAfterStart)));
        var detail = await service.GetByIdAsync(viewing.Id);
        Assert.Equal(allowed, detail!.CanCancel);
        Assert.Null(detail.CancellationDeadline);
        if (allowed)
            Assert.Equal(ViewingStatus.Cancelled, (await service.CancelAsync(viewing.Id, viewing.TenantId)).Status);
        else
            Assert.Equal(ViewingServiceError.Conflict,
                (await Assert.ThrowsAsync<ViewingServiceException>(() => service.CancelAsync(viewing.Id, viewing.TenantId))).Error);
    }

    [Theory]
    [InlineData(ViewingStatus.Cancelled)]
    [InlineData(ViewingStatus.Rejected)]
    [InlineData(ViewingStatus.Completed)]
    public async Task TerminalStatuses_CannotCancel(ViewingStatus status)
    {
        await using var db = Context();
        var viewing = await Seed(db, status);
        var service = new ViewingService(db, new Clock(Start.AddDays(-1)));
        var detail = await service.GetByIdAsync(viewing.Id);
        Assert.False(detail!.CanCancel);
        Assert.Null(detail.CancellationDeadline);
        Assert.Equal(ViewingServiceError.Conflict,
            (await Assert.ThrowsAsync<ViewingServiceException>(() => service.CancelAsync(viewing.Id, viewing.TenantId))).Error);
        Assert.Equal(status, viewing.Status);
    }

    [Fact]
    public async Task StaleEligibility_IsRecheckedUsingServerTime()
    {
        await using var db = Context();
        var viewing = await Seed(db, ViewingStatus.Approved);
        var clock = new Clock(Start.AddHours(-5).AddMinutes(-2));
        var service = new ViewingService(db, clock);
        var stale = await service.GetByIdAsync(viewing.Id);
        Assert.True(stale!.CanCancel);
        clock.Now = clock.Now.AddMinutes(3);
        await Assert.ThrowsAsync<ViewingServiceException>(() => service.CancelAsync(viewing.Id, viewing.TenantId));
        Assert.False((await service.GetByIdAsync(viewing.Id))!.CanCancel);
        Assert.Equal(ViewingStatus.Approved, viewing.Status);
    }

    private static ApplicationDbContext Context() => new(new DbContextOptionsBuilder<ApplicationDbContext>()
        .UseInMemoryDatabase($"ViewingCancellation-{Guid.NewGuid()}").Options);

    private static async Task<ViewingRequest> Seed(ApplicationDbContext db, ViewingStatus status)
    {
        var property = new Property
        {
            LandlordId = Guid.NewGuid(), Title = "Viewing test", Description = "Test home",
            Address = "1 Test Street", City = "Colombo", ViewingTimeZoneId = "Asia/Colombo"
        };
        var viewing = new ViewingRequest
        {
            PropertyId = property.Id, TenantId = Guid.NewGuid(), RequestedDateTime = Start,
            Status = status, DurationMinutes = 60, CreatedAt = Start.AddDays(-1)
        };
        db.AddRange(property, viewing);
        await db.SaveChangesAsync();
        return viewing;
    }
}
