using Microsoft.EntityFrameworkCore;
using RentFlow.Api.Data;
using RentFlow.Api.Models;
using RentFlow.Api.Services;
using Xunit;

namespace RentFlow.Api.Tests.Services;

public sealed class ViewingFollowUpTests
{
    private static readonly DateTimeOffset Start = new(2030, 1, 2, 4, 30, 0, TimeSpan.Zero);
    [Theory]
    [InlineData(15, -1, false)] [InlineData(15, 0, true)] [InlineData(15, 1, true)]
    [InlineData(60, -1, false)] [InlineData(60, 0, true)] [InlineData(120, 0, true)]
    public async Task Completed_UsesStoredDurationAndInclusiveOneHourServerBoundary(int duration, long ticks, bool eligible)
    {
        await using var db = Context(); var (tenant, viewing) = await Seed(db, duration: duration);
        var clock = new ViewingCancellationTests.Clock(Start.AddMinutes(duration + 60).AddTicks(ticks));
        var service = Service(db, clock);
        var claim = await service.ClaimNextAsync(tenant);
        Assert.Equal(eligible, claim is not null);
        Assert.Equal(eligible ? 1 : 0, await db.ViewingFollowUps.CountAsync());
        if (eligible)
        {
            Assert.Equal(viewing.Id, claim!.ViewingId); Assert.Equal(clock.Now, claim.ClaimedAt);
            Assert.Equal(clock.Now + ViewingFollowUpService.ClaimLeaseDuration, claim.ClaimExpiresAt);
            Assert.Equal(claim.ClaimExpiresAt, (await db.ViewingFollowUps.SingleAsync()).ClaimExpiresAt);
            Assert.True(claim.Application.CanApply); Assert.Null(await service.ClaimNextAsync(tenant));
            Assert.Null(await Service(db, clock).ClaimNextAsync(tenant));
        }
        Assert.Empty(db.RentalApplications); Assert.Empty(db.Notifications);
        Assert.Equal(ViewingStatus.Completed, viewing.Status);
    }
    [Theory]
    [InlineData(ViewingStatus.Approved)] [InlineData(ViewingStatus.Pending)]
    [InlineData(ViewingStatus.Cancelled)] [InlineData(ViewingStatus.Rejected)]
    public async Task PassingTime_DoesNotQualifyOtherStatusesOrAutoComplete(ViewingStatus status)
    {
        await using var db = Context(); var (tenant, viewing) = await Seed(db, status);
        Assert.Null(await Service(db, new ViewingCancellationTests.Clock(Start.AddDays(30))).ClaimNextAsync(tenant));
        Assert.Equal(status, viewing.Status); Assert.Empty(db.ViewingFollowUps);
    }
    [Fact]
    public async Task LateCompletion_IsImmediatelyEligible_AndOldestEligibleEndIsFirst()
    {
        await using var db = Context(); var (tenant, newest) = await Seed(db);
        var oldest = new ViewingRequest { TenantId = tenant, PropertyId = newest.PropertyId, Status = ViewingStatus.Completed,
            RequestedDateTime = Start.AddHours(-3), DurationMinutes = 120, UpdatedAt = Start.AddHours(4) };
        var earlyStartButLaterEnd = new ViewingRequest { TenantId = tenant, PropertyId = newest.PropertyId, Status = ViewingStatus.Completed,
            RequestedDateTime = Start.AddHours(-4), DurationMinutes = 300 };
        db.AddRange(oldest, earlyStartButLaterEnd); await db.SaveChangesAsync();
        var service = Service(db, new ViewingCancellationTests.Clock(Start.AddHours(5)));
        Assert.Equal(oldest.Id, (await service.ClaimNextAsync(tenant))!.ViewingId);
        Assert.Equal(1, await db.ViewingFollowUps.CountAsync());
        Assert.NotNull(await service.ClaimNextAsync(tenant)); Assert.Equal(2, await db.ViewingFollowUps.CountAsync());
    }
    [Theory]
    [InlineData(ViewingFollowUpDecision.ApplyNow)] [InlineData(ViewingFollowUpDecision.NotNow)]
    public async Task Response_PersistsOnce_IdempotentRetryKeepsTime_ConflictingResponseRejected(ViewingFollowUpDecision decision)
    {
        await using var db = Context(); var (tenant, viewing) = await Seed(db);
        var clock = new ViewingCancellationTests.Clock(Start.AddHours(4)); var service = Service(db, clock);
        var claim = (await service.ClaimNextAsync(tenant))!;
        clock.Now = claim.ClaimExpiresAt.AddTicks(1); // An open dialog can submit after the lease expires.
        var result = await service.RespondAsync(tenant, claim.FollowUpId, decision);
        Assert.Equal(clock.Now, result.RespondedAt); Assert.Equal(decision.ToString(), result.Decision);
        clock.Now = clock.Now.AddHours(1);
        Assert.Equal(result.RespondedAt, (await service.RespondAsync(tenant, claim.FollowUpId, decision)).RespondedAt);
        Assert.Equal(RentalApplicationServiceError.Conflict, (await Assert.ThrowsAsync<RentalApplicationServiceException>(() =>
            service.RespondAsync(tenant, claim.FollowUpId, decision == ViewingFollowUpDecision.ApplyNow ? ViewingFollowUpDecision.NotNow : ViewingFollowUpDecision.ApplyNow))).Error);
        Assert.Null(await service.ClaimNextAsync(tenant));
        Assert.True((await new RentalApplicationService(db).GetEligibilityAsync(tenant, viewing.PropertyId)).CanApply);
        Assert.Empty(db.RentalApplications);
    }
    [Fact]
    public async Task OwnershipAndUnclaimedResponses_AreNotFound()
    {
        await using var db = Context(); var (tenant, _) = await Seed(db);
        var service = Service(db, new ViewingCancellationTests.Clock(Start.AddDays(2)));
        Assert.Null(await service.ClaimNextAsync(Guid.NewGuid()));
        var claim = (await service.ClaimNextAsync(tenant))!;
        foreach (var input in new[] { (Guid.NewGuid(), claim.FollowUpId), (tenant, Guid.NewGuid()) })
            Assert.Equal(RentalApplicationServiceError.NotFound, (await Assert.ThrowsAsync<RentalApplicationServiceException>(() =>
                service.RespondAsync(input.Item1, input.Item2, ViewingFollowUpDecision.NotNow))).Error);
    }
    [Fact]
    public async Task MissingProperty_IsNotFabricatedAndCreatesNoClaim()
    {
        await using var db = Context(); var (tenant, _) = await Seed(db);
        db.Properties.Remove(await db.Properties.SingleAsync()); await db.SaveChangesAsync();
        Assert.Null(await Service(db, new ViewingCancellationTests.Clock(Start.AddDays(2))).ClaimNextAsync(tenant));
        Assert.Empty(db.ViewingFollowUps);
    }
    [Theory]
    [InlineData(-1, false)] [InlineData(0, true)] [InlineData(1, true)]
    public async Task LeaseBoundary_ReusesSameRowAndRenewsServerTimestamps(long ticks, bool recoverable)
    {
        await using var db = Context(); var (tenant, _) = await Seed(db);
        var clock = new ViewingCancellationTests.Clock(Start.AddHours(4)); var service = Service(db, clock);
        var original = (await service.ClaimNextAsync(tenant))!;
        clock.Now = original.ClaimExpiresAt.AddTicks(ticks);
        var renewed = await service.ClaimNextAsync(tenant);
        var stored = await db.ViewingFollowUps.SingleAsync();
        if (recoverable)
        {
            Assert.NotNull(renewed); Assert.Equal(original.FollowUpId, renewed.FollowUpId);
            Assert.Equal(original.ViewingId, renewed.ViewingId); Assert.Equal(clock.Now, renewed.ClaimedAt);
            Assert.Equal(clock.Now + ViewingFollowUpService.ClaimLeaseDuration, renewed.ClaimExpiresAt);
            Assert.Equal(renewed.ClaimedAt, stored.ClaimedAt); Assert.Equal(renewed.ClaimExpiresAt, stored.ClaimExpiresAt);
            Assert.Null(await service.ClaimNextAsync(tenant));
        }
        else
        {
            Assert.Null(renewed); Assert.Equal(original.ClaimedAt, stored.ClaimedAt);
            Assert.Equal(original.ClaimExpiresAt, stored.ClaimExpiresAt);
        }
        Assert.Equal(original.FollowUpId, stored.Id); Assert.Null(stored.Decision); Assert.Null(stored.RespondedAt);
    }
    [Theory]
    [InlineData(false)] [InlineData(true)]
    public async Task OlderUnresolvedClaim_WithExpiredOrLegacyNullLease_PrecedesNewViewing(bool legacy)
    {
        await using var db = Context(); var (tenant, newest) = await Seed(db);
        var oldest = new ViewingRequest { TenantId = tenant, PropertyId = newest.PropertyId, Status = ViewingStatus.Completed,
            RequestedDateTime = Start.AddDays(-1), DurationMinutes = 45 };
        var original = new ViewingFollowUp { TenantId = tenant, ViewingId = oldest.Id, ClaimedAt = Start.AddHours(-2),
            ClaimExpiresAt = legacy ? null : Start.AddHours(-1) };
        db.AddRange(oldest, original); await db.SaveChangesAsync();
        var clock = new ViewingCancellationTests.Clock(Start.AddHours(4)); var service = Service(db, clock);
        var recovered = (await service.ClaimNextAsync(tenant))!;
        Assert.Equal(original.Id, recovered.FollowUpId); Assert.Equal(oldest.Id, recovered.ViewingId);
        Assert.Equal(clock.Now, recovered.ClaimedAt); Assert.Equal(clock.Now + ViewingFollowUpService.ClaimLeaseDuration, recovered.ClaimExpiresAt);
        Assert.Single(db.ViewingFollowUps); Assert.Null(original.Decision); Assert.Null(original.RespondedAt);
        Assert.Equal(newest.Id, (await service.ClaimNextAsync(tenant))!.ViewingId);
        Assert.Equal(2, await db.ViewingFollowUps.CountAsync()); Assert.Null(await service.ClaimNextAsync(tenant));
    }
    [Theory]
    [InlineData(ViewingFollowUpDecision.ApplyNow)] [InlineData(ViewingFollowUpDecision.NotNow)]
    public async Task LegacyRespondedRows_NeverRecover(ViewingFollowUpDecision decision)
    {
        await using var db = Context(); var (tenant, viewing) = await Seed(db);
        db.Add(new ViewingFollowUp { TenantId = tenant, ViewingId = viewing.Id, ClaimedAt = Start,
            Decision = decision, RespondedAt = Start.AddHours(2) }); await db.SaveChangesAsync();
        Assert.Null(await Service(db, new ViewingCancellationTests.Clock(Start.AddYears(10))).ClaimNextAsync(tenant));
        Assert.Single(db.ViewingFollowUps);
    }
    private static ApplicationDbContext Context() => new(new DbContextOptionsBuilder<ApplicationDbContext>().UseInMemoryDatabase(Guid.NewGuid().ToString()).Options);
    private static ViewingFollowUpService Service(ApplicationDbContext db, TimeProvider clock) => new(db, clock, new RentalApplicationService(db));
    private static async Task<(Guid Tenant, ViewingRequest Viewing)> Seed(ApplicationDbContext db, ViewingStatus status = ViewingStatus.Completed, int duration = 60)
    {
        var tenant = Guid.NewGuid(); var property = new Property { Title = "Real viewed home", Address = "Garden street", City = "Colombo", ViewingSlotDurationMinutes = 90 };
        var viewing = new ViewingRequest { TenantId = tenant, PropertyId = property.Id, Status = status, RequestedDateTime = Start, DurationMinutes = duration,
            UpdatedAt = status == ViewingStatus.Completed ? Start.AddHours(4) : null };
        db.AddRange(property, viewing); await db.SaveChangesAsync(); return (tenant, viewing);
    }
}
