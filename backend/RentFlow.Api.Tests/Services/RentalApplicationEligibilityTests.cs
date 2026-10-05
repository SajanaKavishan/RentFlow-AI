using Microsoft.EntityFrameworkCore;
using RentFlow.Api.Data;
using RentFlow.Api.DTOs.RentalApplications;
using RentFlow.Api.Models;
using RentFlow.Api.Services;
using Xunit;

namespace RentFlow.Api.Tests.Services;

public sealed class RentalApplicationEligibilityTests
{
    [Theory]
    [InlineData(null)]
    [InlineData(ViewingStatus.Pending)]
    [InlineData(ViewingStatus.Approved)]
    [InlineData(ViewingStatus.Rejected)]
    [InlineData(ViewingStatus.Cancelled)]
    [InlineData(ViewingStatus.Completed)]
    public async Task SameTenantProperty_OnlyCompletedAllowsCreationAndSubmission(ViewingStatus? status)
    {
        await using var db = Context();
        var property = Property();
        var tenant = Guid.NewGuid();
        db.Add(property);
        if (status.HasValue) db.Add(new ViewingRequest { TenantId = tenant, PropertyId = property.Id, Status = status.Value });
        await db.SaveChangesAsync();
        var service = new RentalApplicationService(db);
        var eligibility = await service.GetEligibilityAsync(tenant, property.Id);
        Assert.Equal(status == ViewingStatus.Completed, eligibility.CanApply);
        Assert.Equal(eligibility.CanApply, eligibility.HasCompletedViewing);
        if (eligibility.CanApply)
        {
            var created = await service.CreateAsync(tenant, Request(property.Id));
            Assert.Equal(RentalApplicationStatus.Draft, created.Status);
            var submitted = await service.SubmitAsync(created.Id, tenant);
            Assert.Equal(RentalApplicationStatus.Submitted, submitted.Status);
        }
        else
        {
            Assert.Equal(RentalApplicationServiceError.Conflict,
                (await Assert.ThrowsAsync<RentalApplicationServiceException>(() => service.CreateAsync(tenant, Request(property.Id)))).Error);
            var draft = Draft(tenant, property.Id);
            db.Add(draft);
            await db.SaveChangesAsync();
            var error = await Assert.ThrowsAsync<RentalApplicationServiceException>(() => service.SubmitAsync(draft.Id, tenant));
            Assert.Equal(RentalApplicationServiceError.Conflict, error.Error);
            db.ChangeTracker.Clear();
            var stored = await db.RentalApplications.SingleAsync();
            Assert.Equal(RentalApplicationStatus.Draft, stored.Status);
            Assert.Null(stored.SubmittedAt);
            Assert.Null(stored.UpdatedAt);
            Assert.Equal("Saved note", stored.TenantNote);
            Assert.Empty(db.Notifications);
        }
    }

    [Theory]
    [InlineData(true)]
    [InlineData(false)]
    public async Task CompletedViewing_CannotTransferBetweenTenantOrProperty(bool otherTenant)
    {
        await using var db = Context();
        var property = Property();
        var tenant = Guid.NewGuid();
        db.Add(property);
        db.Add(new ViewingRequest { TenantId = otherTenant ? Guid.NewGuid() : tenant,
            PropertyId = otherTenant ? property.Id : Guid.NewGuid(), Status = ViewingStatus.Completed });
        await db.SaveChangesAsync();
        var service = new RentalApplicationService(db);
        Assert.False((await service.GetEligibilityAsync(tenant, property.Id)).CanApply);
        Assert.Empty(await service.GetEligiblePropertiesAsync(tenant));
        await Assert.ThrowsAsync<RentalApplicationServiceException>(() => service.CreateAsync(tenant, Request(property.Id)));
    }

    [Theory]
    [InlineData(RentalApplicationStatus.Draft)]
    [InlineData(RentalApplicationStatus.Submitted)]
    [InlineData(RentalApplicationStatus.UnderReview)]
    [InlineData(RentalApplicationStatus.ChangesRequested)]
    [InlineData(RentalApplicationStatus.Approved)]
    [InlineData(RentalApplicationStatus.Rejected)]
    [InlineData(RentalApplicationStatus.Withdrawn)]
    public async Task ExistingApplication_PreservesActiveDuplicateAndReapplicationPolicy(RentalApplicationStatus status)
    {
        await using var db = Context();
        var property = Property();
        var tenant = Guid.NewGuid();
        var existing = Draft(tenant, property.Id);
        existing.Status = status;
        db.AddRange(property, existing, new ViewingRequest { TenantId = tenant, PropertyId = property.Id, Status = ViewingStatus.Completed });
        await db.SaveChangesAsync();
        var service = new RentalApplicationService(db);
        var active = status is RentalApplicationStatus.Draft or RentalApplicationStatus.Submitted or RentalApplicationStatus.UnderReview or RentalApplicationStatus.ChangesRequested;
        var result = await service.GetEligibilityAsync(tenant, property.Id);
        Assert.True(result.HasCompletedViewing);
        Assert.Equal(!active, result.CanApply);
        Assert.Equal(active ? existing.Id : (Guid?)null, result.ExistingApplicationId);
        Assert.Equal(active ? status : (RentalApplicationStatus?)null, result.ExistingApplicationStatus);
        Assert.Equal(active ? 0 : 1, (await service.GetEligiblePropertiesAsync(tenant)).Count);
        if (active) await Assert.ThrowsAsync<RentalApplicationServiceException>(() => service.CreateAsync(tenant, Request(property.Id)));
        else Assert.Equal(RentalApplicationStatus.Draft, (await service.CreateAsync(tenant, Request(property.Id))).Status);
    }

    [Fact]
    public async Task Picker_DistinctAvailablePropertiesAndOnlyCurrentTenantsHistory()
    {
        await using var db = Context();
        var tenant = Guid.NewGuid();
        var eligible = Property(); var unavailable = Property(); unavailable.IsAvailable = false;
        var pending = Property(); var otherTenant = Property();
        db.AddRange(eligible, unavailable, pending, otherTenant);
        db.AddRange(new ViewingRequest { TenantId = tenant, PropertyId = eligible.Id, Status = ViewingStatus.Completed },
            new ViewingRequest { TenantId = tenant, PropertyId = eligible.Id, Status = ViewingStatus.Completed },
            new ViewingRequest { TenantId = tenant, PropertyId = unavailable.Id, Status = ViewingStatus.Completed },
            new ViewingRequest { TenantId = tenant, PropertyId = pending.Id, Status = ViewingStatus.Approved },
            new ViewingRequest { TenantId = Guid.NewGuid(), PropertyId = otherTenant.Id, Status = ViewingStatus.Completed });
        await db.SaveChangesAsync();
        var service = new RentalApplicationService(db);
        Assert.Equal(eligible.Id, Assert.Single(await service.GetEligiblePropertiesAsync(tenant)).Id);
        Assert.False((await service.GetEligibilityAsync(tenant, unavailable.Id)).CanApply);
        await Assert.ThrowsAsync<RentalApplicationServiceException>(() => service.CreateAsync(tenant, Request(unavailable.Id)));
    }

    [Theory]
    [InlineData(RentalApplicationStatus.Draft)]
    [InlineData(RentalApplicationStatus.ChangesRequested)]
    public async Task LegacyDraft_RemainsEditableButSubmissionRequiresCompletedViewing(RentalApplicationStatus status)
    {
        await using var db = Context();
        var property = Property(); var tenant = Guid.NewGuid(); var draft = Draft(tenant, property.Id); draft.Status = status;
        db.AddRange(property, draft); await db.SaveChangesAsync();
        var service = new RentalApplicationService(db);
        var updated = await service.UpdateAsync(draft.Id, tenant, new UpdateRentalApplicationDto
        { MoveInDate = draft.MoveInDate, MonthlyIncome = 9000, Occupation = "Updated occupation", NumberOfOccupants = 2, TenantNote = "Preserved data" });
        Assert.Equal(draft.Id, updated.Id);
        var updatedAt = updated.UpdatedAt;
        await Assert.ThrowsAsync<RentalApplicationServiceException>(() => service.SubmitAsync(draft.Id, tenant));
        Assert.Equal(status, draft.Status); Assert.Equal(updatedAt, draft.UpdatedAt);
        Assert.Equal("Preserved data", draft.TenantNote);
        Assert.Equal(draft.Id, (await service.GetEligibilityAsync(tenant, property.Id)).ExistingApplicationId);
        db.Add(new ViewingRequest { TenantId = tenant, PropertyId = property.Id, Status = ViewingStatus.Completed }); await db.SaveChangesAsync();
        Assert.Equal(RentalApplicationStatus.Submitted, (await service.SubmitAsync(draft.Id, tenant)).Status);
        Assert.Equal(1, await db.RentalApplications.CountAsync());
    }

    [Fact]
    public async Task MissingProperty_DoesNotGainEligibilityFromOrphanViewing()
    {
        await using var db = Context(); var tenant = Guid.NewGuid(); var propertyId = Guid.NewGuid();
        db.Add(new ViewingRequest { TenantId = tenant, PropertyId = propertyId, Status = ViewingStatus.Completed }); await db.SaveChangesAsync();
        var service = new RentalApplicationService(db);
        Assert.Equal(RentalApplicationServiceError.NotFound,
            (await Assert.ThrowsAsync<RentalApplicationServiceException>(() => service.GetEligibilityAsync(tenant, propertyId))).Error);
        Assert.Empty(await service.GetEligiblePropertiesAsync(tenant));
        await Assert.ThrowsAsync<RentalApplicationServiceException>(() => service.CreateAsync(tenant, Request(propertyId)));
    }

    private static ApplicationDbContext Context() => new(new DbContextOptionsBuilder<ApplicationDbContext>().UseInMemoryDatabase($"Eligibility-{Guid.NewGuid()}").Options);
    private static Property Property() => new() { LandlordId = Guid.NewGuid(), Title = "Viewed home", Address = "Test street", City = "Colombo", MonthlyRent = 100000 };
    private static CreateRentalApplicationDto Request(Guid propertyId) => new()
    { PropertyId = propertyId, MoveInDate = DateOnly.FromDateTime(DateTime.UtcNow.AddDays(30)), MonthlyIncome = 7500, Occupation = "Engineer", NumberOfOccupants = 1 };
    private static RentalApplication Draft(Guid tenant, Guid property) => new()
    { TenantId = tenant, PropertyId = property, MoveInDate = DateOnly.FromDateTime(DateTime.UtcNow.AddDays(30)), MonthlyIncome = 7500, Occupation = "Engineer", NumberOfOccupants = 1, TenantNote = "Saved note" };
}
