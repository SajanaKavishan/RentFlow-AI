using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using RentFlow.Api.Data;
using RentFlow.Api.Models;
using RentFlow.Api.Services;
using RentFlow.Api.Services.Interfaces;
using Xunit;

namespace RentFlow.Api.Tests.Services;

public sealed class ViewingCompletionTests
{
    internal sealed class Actor(Guid? id, UserRole? role, bool authenticated = true) : ICurrentUserService
    {
        public bool IsAuthenticated => authenticated;
        public Guid? UserId => id;
        public UserRole? Role => role;
    }

    private static readonly DateTimeOffset Start = new(2030, 1, 2, 4, 30, 0, TimeSpan.Zero);

    [Theory]
    [InlineData(15, -1, false)]
    [InlineData(15, 0, true)]
    [InlineData(15, 1, true)]
    [InlineData(60, -1, false)]
    [InlineData(60, 0, true)]
    [InlineData(60, 1, true)]
    [InlineData(120, -1, false)]
    [InlineData(120, 0, true)]
    [InlineData(120, 1, true)]
    public async Task Completion_UsesStoredDurationAndInclusiveServerEnd(int duration, long ticksAfterEnd, bool allowed)
    {
        await using var db = Context();
        var (viewing, property) = await Seed(db, duration: duration);
        // Current schedule duration must not replace the booking's duration snapshot.
        property.ViewingSlotDurationMinutes = duration == 15 ? 120 : 15;
        await db.SaveChangesAsync();
        var end = Start.AddMinutes(duration);
        var clock = new ViewingCancellationTests.Clock(end.AddTicks(ticksAfterEnd));
        var service = new ViewingService(db, clock, new Actor(property.LandlordId, UserRole.Landlord));
        var detail = (await service.GetByIdAsync(viewing.Id))!;
        var list = Assert.Single(await service.GetByPropertyAsync(property.Id));
        Assert.Equal(allowed, detail.CanMarkCompleted);
        Assert.Equal(end, detail.CompletionEligibleAt);
        Assert.Equal(detail.CanMarkCompleted, list.CanMarkCompleted);
        Assert.Equal(end, list.CompletionEligibleAt);
        // Passing time and reading eligibility never complete a viewing.
        Assert.Equal(ViewingStatus.Approved, detail.Status);
        if (allowed)
        {
            var result = await service.CompleteAsync(viewing.Id);
            Assert.Equal(ViewingStatus.Completed, result.Status);
            Assert.Equal(clock.Now, result.UpdatedAt);
            Assert.False(result.CanMarkCompleted);
            Assert.Null(result.CompletionEligibleAt);
            Assert.Null(result.Tenant.PhoneNumber);
            clock.Now = clock.Now.AddMinutes(1);
            Assert.Equal(ViewingServiceError.Conflict,
                (await Assert.ThrowsAsync<ViewingServiceException>(() => service.CompleteAsync(viewing.Id))).Error);
        }
        else
        {
            var error = await Assert.ThrowsAsync<ViewingServiceException>(() => service.CompleteAsync(viewing.Id));
            Assert.Equal(ViewingServiceError.Conflict, error.Error);
            Assert.Equal("This viewing can only be marked completed after the scheduled viewing has ended.", error.Message);
        }
        db.ChangeTracker.Clear();
        var stored = await db.ViewingRequests.SingleAsync();
        Assert.Equal(allowed ? ViewingStatus.Completed : ViewingStatus.Approved, stored.Status);
        Assert.Equal(allowed ? end.AddTicks(ticksAfterEnd) : (DateTimeOffset?)null, stored.UpdatedAt);
        Assert.Equal(Start, stored.RequestedDateTime);
        Assert.Equal(duration, stored.DurationMinutes);
        Assert.Equal(viewing.TenantId, stored.TenantId);
        Assert.Equal(viewing.PropertyId, stored.PropertyId);
        Assert.Equal("Tenant note", stored.TenantMessage);
        Assert.Equal("Landlord response", stored.LandlordResponse);
        Assert.Equal(viewing.CreatedAt, stored.CreatedAt);
        Assert.Empty(await db.Notifications.ToListAsync());
    }

    [Theory]
    [InlineData(ViewingStatus.Pending)]
    [InlineData(ViewingStatus.Rejected)]
    [InlineData(ViewingStatus.Cancelled)]
    [InlineData(ViewingStatus.Completed)]
    public async Task NonApprovedStatuses_RejectCompletionAndHaveNoEligibility(ViewingStatus status)
    {
        await using var db = Context();
        var (viewing, property) = await Seed(db, status);
        var service = new ViewingService(db, new ViewingCancellationTests.Clock(Start.AddDays(1)),
            new Actor(property.LandlordId, UserRole.Landlord));
        var response = (await service.GetByIdAsync(viewing.Id))!;
        Assert.False(response.CanMarkCompleted);
        Assert.Null(response.CompletionEligibleAt);
        Assert.Equal(ViewingServiceError.Conflict,
            (await Assert.ThrowsAsync<ViewingServiceException>(() => service.CompleteAsync(viewing.Id))).Error);
        Assert.Equal(status, viewing.Status);
        Assert.Null(viewing.UpdatedAt);
    }

    [Theory]
    [InlineData(UserRole.Landlord, false, true)]
    [InlineData(UserRole.Tenant, true, true)]
    [InlineData(UserRole.MaintenanceTechnician, true, true)]
    [InlineData(UserRole.Landlord, true, false)]
    public async Task Service_RejectsUnauthorizedActorsEvenWithoutController(UserRole role, bool owner, bool authenticated)
    {
        await using var db = Context();
        var (viewing, property) = await Seed(db);
        var service = new ViewingService(db, new ViewingCancellationTests.Clock(Start.AddDays(1)),
            new Actor(owner ? property.LandlordId : Guid.NewGuid(), role, authenticated));
        Assert.False((await service.GetByIdAsync(viewing.Id))!.CanMarkCompleted);
        Assert.False(Assert.Single(await service.GetByPropertyAsync(property.Id)).CanMarkCompleted);
        Assert.Equal(ViewingServiceError.NotFound,
            (await Assert.ThrowsAsync<ViewingServiceException>(() => service.CompleteAsync(viewing.Id))).Error);
        Assert.Equal(ViewingStatus.Approved, viewing.Status);
        Assert.Null(viewing.UpdatedAt);
    }

    [Fact]
    public async Task MissingActor_FailsClosed()
    {
        await using var db = Context();
        var (viewing, _) = await Seed(db);
        var service = new ViewingService(db, new ViewingCancellationTests.Clock(Start.AddDays(1)));
        Assert.False((await service.GetByIdAsync(viewing.Id))!.CanMarkCompleted);
        await Assert.ThrowsAsync<ViewingServiceException>(() => service.CompleteAsync(viewing.Id));
        Assert.Equal(ViewingStatus.Approved, viewing.Status);
    }

    [Theory]
    [InlineData(330)]
    [InlineData(-420)]
    public async Task EndComparison_UsesInstantsIndependentOfOffset(int offsetMinutes)
    {
        await using var db = Context();
        var (viewing, property) = await Seed(db);
        viewing.RequestedDateTime = Start.ToOffset(TimeSpan.FromMinutes(offsetMinutes));
        await db.SaveChangesAsync();
        var clock = new ViewingCancellationTests.Clock(Start.AddMinutes(60).AddTicks(-1));
        var service = new ViewingService(db, clock, new Actor(property.LandlordId, UserRole.Landlord));
        await Assert.ThrowsAsync<ViewingServiceException>(() => service.CompleteAsync(viewing.Id));
        clock.Now = clock.Now.AddTicks(1);
        Assert.Equal(ViewingStatus.Completed, (await service.CompleteAsync(viewing.Id)).Status);
    }

    [Theory]
    [InlineData(0)]
    [InlineData(-15)]
    public async Task InvalidDuration_FailsClosedWithoutBackfill(int duration)
    {
        await using var db = Context();
        var (viewing, property) = await Seed(db, duration: duration);
        var service = new ViewingService(db, new ViewingCancellationTests.Clock(Start.AddDays(1)),
            new Actor(property.LandlordId, UserRole.Landlord));
        var result = (await service.GetByIdAsync(viewing.Id))!;
        Assert.False(result.CanMarkCompleted);
        Assert.Null(result.CompletionEligibleAt);
        Assert.Equal(ViewingServiceError.Conflict,
            (await Assert.ThrowsAsync<ViewingServiceException>(() => service.CompleteAsync(viewing.Id))).Error);
        Assert.Equal(duration, viewing.DurationMinutes);
    }

    [Fact]
    public async Task StaleEligibility_RechecksTimeStatusAndOwnership()
    {
        await using var db = Context();
        var (viewing, property) = await Seed(db);
        var clock = new ViewingCancellationTests.Clock(Start.AddMinutes(60).AddTicks(-1));
        var actor = new Actor(property.LandlordId, UserRole.Landlord);
        var service = new ViewingService(db, clock, actor);
        Assert.False((await service.GetByIdAsync(viewing.Id))!.CanMarkCompleted);
        clock.Now = clock.Now.AddTicks(1);
        Assert.True((await service.GetByIdAsync(viewing.Id))!.CanMarkCompleted);
        // Another request changes persisted state while this context still tracks Approved.
        await using (var other = new ApplicationDbContext((DbContextOptions<ApplicationDbContext>)db.GetService<IDbContextOptions>()))
        {
            var stored = await other.ViewingRequests.SingleAsync();
            stored.Status = ViewingStatus.Cancelled;
            await other.SaveChangesAsync();
        }
        Assert.Equal(ViewingServiceError.Conflict,
            (await Assert.ThrowsAsync<ViewingServiceException>(() => service.CompleteAsync(viewing.Id))).Error);
        viewing.Status = ViewingStatus.Approved;
        property.LandlordId = Guid.NewGuid();
        await db.SaveChangesAsync();
        Assert.Equal(ViewingServiceError.NotFound,
            (await Assert.ThrowsAsync<ViewingServiceException>(() => service.CompleteAsync(viewing.Id))).Error);
        Assert.Equal(ViewingStatus.Approved, viewing.Status);
    }

    private static ApplicationDbContext Context() => new(new DbContextOptionsBuilder<ApplicationDbContext>()
        .UseInMemoryDatabase($"ViewingCompletion-{Guid.NewGuid()}").Options);

    private static async Task<(ViewingRequest, Property)> Seed(ApplicationDbContext db,
        ViewingStatus status = ViewingStatus.Approved, int duration = 60)
    {
        var property = new Property
        {
            LandlordId = Guid.NewGuid(), Title = "Viewing test", Description = "Test home",
            Address = "1 Test Street", City = "Colombo", ViewingTimeZoneId = "Asia/Colombo"
        };
        var viewing = new ViewingRequest
        {
            PropertyId = property.Id, TenantId = Guid.NewGuid(), RequestedDateTime = Start,
            DurationMinutes = duration, Status = status, CreatedAt = Start.AddDays(-1),
            TenantMessage = "Tenant note", LandlordResponse = "Landlord response"
        };
        db.AddRange(property, viewing);
        await db.SaveChangesAsync();
        return (viewing, property);
    }
}
