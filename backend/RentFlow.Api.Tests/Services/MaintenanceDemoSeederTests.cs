using Microsoft.EntityFrameworkCore;
using RentFlow.Api.Data;
using RentFlow.Api.Models;
using RentFlow.DevTools;
using Xunit;

namespace RentFlow.Api.Tests.Services;

public sealed class MaintenanceDemoSeederTests
{
    [Theory]
    [InlineData("Host=database.example;Database=rentflow_dev;Username=test", "Development")]
    [InlineData("Host=localhost;Database=rentflow_dev;Username=test", "Production")]
    [InlineData("Host=localhost;Database=rentflow_dev;Username=test", "Staging")]
    [InlineData("Host=localhost;Database=rentflow_prod;Username=test", "Development")]
    public void RemoteOrNonDevelopmentDatabase_IsRejected(string connection, string environment) =>
        Assert.Throws<MaintenanceDemoSetupException>(() => MaintenanceDemoSeeder.ValidateLocalDevelopment(connection, environment));

    [Theory]
    [InlineData("localhost")]
    [InlineData("127.0.0.1")]
    [InlineData("::1")]
    public void LoopbackDevelopmentDatabase_IsAllowed(string host) =>
        MaintenanceDemoSeeder.ValidateLocalDevelopment($"Host={host};Database=rentflow_dev;Username=test", "Development");

    [Fact]
    public async Task DryRun_DoesNotWriteOrModifyTheLandlord()
    {
        await using var db = Context();
        var landlord = Landlord();
        db.Users.Add(landlord);
        await db.SaveChangesAsync();
        var result = await MaintenanceDemoSeeder.CreateAsync(db, landlord.Email, DateTimeOffset.UtcNow, true);
        Assert.Equal(Guid.Empty, result.PropertyId);
        Assert.Single(db.Users);
        Assert.Empty(db.Properties);
        Assert.Empty(db.LeaseAgreements);
        Assert.Empty(db.MaintenanceRequests);
        Assert.Equal("unchanged-password-hash", landlord.PasswordHash);
    }

    [Theory]
    [InlineData(UserRole.Tenant, true)]
    [InlineData(UserRole.Admin, true)]
    [InlineData(UserRole.Landlord, false)]
    public async Task NonLandlordOrInactiveAccount_CannotReceiveFixtureData(UserRole role, bool active)
    {
        await using var db = Context();
        var user = Landlord();
        user.Role = role;
        user.IsActive = active;
        db.Users.Add(user);
        await db.SaveChangesAsync();
        await Assert.ThrowsAsync<MaintenanceDemoSetupException>(() =>
            MaintenanceDemoSeeder.CreateAsync(db, user.Email, DateTimeOffset.UtcNow, false));
        Assert.Single(db.Users);
        Assert.Empty(db.Properties);
        Assert.Empty(db.MaintenanceRequests);
    }

    [Fact]
    public async Task CreatedFixtures_HaveOwnedPropertyCurrentLeaseAndSubmittedRequests_RerunPreservesChanges()
    {
        await using var db = Context();
        var landlord = Landlord();
        db.Users.Add(landlord);
        await db.SaveChangesAsync();
        var now = DateTimeOffset.UtcNow;
        var result = await MaintenanceDemoSeeder.CreateAsync(db, landlord.Email.ToUpperInvariant(), now, false);
        Assert.True(result.Created);
        Assert.NotNull(result.NewTenantPassword);
        var property = await db.Properties.SingleAsync();
        Assert.Equal(landlord.Id, property.LandlordId);
        var tenant = await db.Users.SingleAsync(user => user.Role == UserRole.Tenant);
        Assert.Equal(result.TenantEmail, tenant.Email);
        Assert.Equal(LeaseAgreementStatus.Active, (await db.LeaseAgreements.SingleAsync()).Status);
        var lease = await db.LeaseAgreements.SingleAsync();
        Assert.True(lease.StartDate <= DateOnly.FromDateTime(now.UtcDateTime));
        Assert.True(lease.EndDate >= DateOnly.FromDateTime(now.UtcDateTime));
        Assert.Equal(property.Id, lease.PropertyId);
        Assert.Equal(tenant.Id, lease.TenantId);
        Assert.Equal(RentalApplicationStatus.Approved, (await db.RentalApplications.SingleAsync()).Status);
        Assert.Equal(RentalOfferStatus.Accepted, (await db.RentalOffers.SingleAsync()).Status);
        var requests = await db.MaintenanceRequests.ToListAsync();
        Assert.Equal(2, requests.Count);
        Assert.Equal(2, db.MaintenanceStatusHistories.Count());
        Assert.All(requests, request => {
            Assert.Equal(MaintenanceRequestStatus.Submitted, request.Status);
            Assert.Equal(property.Id, request.PropertyId);
            Assert.Equal(tenant.Id, request.TenantId);
            Assert.Matches("^MR-[A-F0-9]{16}$", request.ReferenceCode);
            Assert.NotNull(request.PreferredAccessWindow);
        });
        requests[0].Status = MaintenanceRequestStatus.Triaged;
        await db.SaveChangesAsync();
        var second = await MaintenanceDemoSeeder.CreateAsync(db, landlord.Email, now, false);
        Assert.False(second.Created);
        Assert.Null(second.NewTenantPassword);
        Assert.Equal(result.PropertyId, second.PropertyId);
        Assert.Equal(2, db.Users.Count());
        Assert.Single(db.Properties);
        Assert.Equal(2, db.MaintenanceRequests.Count());
        Assert.Equal(MaintenanceRequestStatus.Triaged, requests[0].Status);
        Assert.Equal("unchanged-password-hash", landlord.PasswordHash);
        Assert.Empty(db.MaintenanceCoordinationWorkflows);
        Assert.Empty(db.MaintenanceAttachments);
    }

    private static ApplicationDbContext Context() => new(new DbContextOptionsBuilder<ApplicationDbContext>()
        .UseInMemoryDatabase(Guid.NewGuid().ToString()).Options);
    private static ApplicationUser Landlord() => new() {
        Id = Guid.NewGuid(), FullName = "Existing development Landlord", Email = "landlord@example.test",
        NormalizedEmail = "LANDLORD@EXAMPLE.TEST", PhoneNumber = "+94770000000", PasswordHash = "unchanged-password-hash",
        Role = UserRole.Landlord, IsActive = true,
    };
}
