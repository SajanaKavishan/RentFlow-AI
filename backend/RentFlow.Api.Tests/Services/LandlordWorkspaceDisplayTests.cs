using Microsoft.EntityFrameworkCore;
using RentFlow.Api.Data;
using RentFlow.Api.Models;
using RentFlow.Api.Services;
using Xunit;

namespace RentFlow.Api.Tests.Services;

public sealed class LandlordWorkspaceDisplayTests
{
    [Fact]
    public async Task ApplicationDisplay_UsesRelatedNamesAndTitles_WithoutChangingStoredRequest()
    {
        await using var db = new ApplicationDbContext(new DbContextOptionsBuilder<ApplicationDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString()).Options);
        var tenant = new ApplicationUser { Id = Guid.NewGuid(), FullName = "Nimal Perera", Email = "private@example.test",
            PhoneNumber = "+94 77 123 4567", PasswordHash = "private-hash", Role = UserRole.Tenant };
        var property = new Property { Id = Guid.NewGuid(), LandlordId = Guid.NewGuid(), Title = "Garden House" };
        var application = new RentalApplication { TenantId = tenant.Id, PropertyId = property.Id,
            Status = RentalApplicationStatus.Submitted, MonthlyIncome = 250000, Occupation = "Engineer",
            SubmittedAt = DateTimeOffset.UtcNow, MoveInDate = new DateOnly(2030, 2, 1), NumberOfOccupants = 2 };
        var unrelated = new RentalApplication { TenantId = Guid.NewGuid(), PropertyId = Guid.NewGuid() };
        db.AddRange(tenant, property, application, unrelated);
        await db.SaveChangesAsync();
        var service = new RentalApplicationService(db);
        var detail = (await service.GetByIdAsync(application.Id))!;
        var list = Assert.Single(await service.GetByPropertyAsync(property.Id));
        Assert.Equal("Garden House", detail.PropertyTitle);
        Assert.Equal("Nimal Perera", detail.ApplicantName);
        Assert.Equal(detail.PropertyTitle, list.PropertyTitle);
        Assert.Equal(detail.ApplicantName, list.ApplicantName);
        Assert.Equal(RentalApplicationStatus.Submitted, application.Status);
        Assert.Equal(application.SubmittedAt, detail.SubmittedAt);
        var json = System.Text.Json.JsonSerializer.Serialize(detail);
        Assert.DoesNotContain(tenant.Email, json);
        Assert.DoesNotContain(tenant.PhoneNumber, json);
        Assert.DoesNotContain(tenant.PasswordHash, json);
        Assert.Null(await service.GetByIdForTenantAsync(application.Id, unrelated.TenantId));
    }

    [Fact]
    public async Task ViewingDisplay_UsesRealTitleInListAndDetail()
    {
        await using var db = new ApplicationDbContext(new DbContextOptionsBuilder<ApplicationDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString()).Options);
        var property = new Property { Id = Guid.NewGuid(), LandlordId = Guid.NewGuid(), Title = "Garden House" };
        var viewing = new ViewingRequest { PropertyId = property.Id, TenantId = Guid.NewGuid(), DurationMinutes = 60 };
        db.AddRange(property, viewing);
        await db.SaveChangesAsync();
        var service = new ViewingService(db);
        var detail = (await service.GetByIdAsync(viewing.Id))!;
        var list = Assert.Single(await service.GetByPropertyAsync(property.Id));
        Assert.Equal(property.Title, detail.PropertyTitle);
        Assert.Equal(property.Title, list.PropertyTitle);
        Assert.Equal(60, detail.DurationMinutes);
        Assert.Null(list.Tenant.PhoneNumber);
        Assert.Equal(ViewingStatus.Pending, viewing.Status);
    }
}
