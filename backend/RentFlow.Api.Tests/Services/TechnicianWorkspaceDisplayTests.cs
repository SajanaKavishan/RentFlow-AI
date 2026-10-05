using Microsoft.EntityFrameworkCore;
using RentFlow.Api.Data;
using RentFlow.Api.Models;
using RentFlow.Api.Services;
using Xunit;

namespace RentFlow.Api.Tests.Services;

public sealed class TechnicianWorkspaceDisplayTests
{
    [Fact]
    public async Task QueueAndDetails_ReturnRealPropertyAndRequesterDisplayData()
    {
        await using var db = Context();
        var tenant = new ApplicationUser { Id = Guid.NewGuid(), FullName = "Nimal Perera", Role = UserRole.Tenant,
            Email = "private@example.test", PhoneNumber = "+94771234567", PasswordHash = "private-hash" };
        var technicianId = Guid.NewGuid();
        var property = new Property { Title = "Garden House", Address = "12 Lake Road", City = "Colombo", LandlordId = Guid.NewGuid() };
        var request = new MaintenanceRequest { PropertyId = property.Id, TenantId = tenant.Id, TechnicianId = technicianId,
            Title = "Repair sink", Description = "Leaking tap", Status = MaintenanceRequestStatus.InProgress };
        var unrelated = new MaintenanceRequest { TechnicianId = Guid.NewGuid(), Title = "Other technician's work" };
        db.AddRange(tenant, property, request, unrelated);
        await db.SaveChangesAsync();
        var service = new MaintenanceRequestService(db);
        var summary = Assert.Single(await service.GetByTechnicianAsync(technicianId));
        var detail = (await service.GetByIdAsync(request.Id))!;
        Assert.Equal(request.Id, summary.Id);
        Assert.Equal("Garden House", summary.PropertyTitle);
        Assert.Equal("12 Lake Road", summary.PropertyAddress);
        Assert.Equal("Colombo", summary.PropertyCity);
        Assert.Equal("Nimal Perera", summary.RequesterName);
        Assert.Equal(summary.PropertyTitle, detail.PropertyTitle);
        Assert.Equal(summary.PropertyAddress, detail.PropertyAddress);
        Assert.Equal(summary.PropertyCity, detail.PropertyCity);
        Assert.Equal(summary.RequesterName, detail.RequesterName);
        Assert.Equal(MaintenanceRequestStatus.InProgress, request.Status);
        foreach (var json in new[] { System.Text.Json.JsonSerializer.Serialize(summary), System.Text.Json.JsonSerializer.Serialize(detail) })
        {
            Assert.DoesNotContain(tenant.Email, json);
            Assert.DoesNotContain(tenant.PhoneNumber, json);
            Assert.DoesNotContain(tenant.PasswordHash, json);
        }
    }

    [Fact]
    public async Task MissingRelatedRecords_KeepNamesNullWithoutInventingDisplayData()
    {
        await using var db = Context();
        var request = new MaintenanceRequest { PropertyId = Guid.NewGuid(), TenantId = Guid.NewGuid(), TechnicianId = Guid.NewGuid(), Title = "Legacy work" };
        db.Add(request);
        await db.SaveChangesAsync();
        var service = new MaintenanceRequestService(db);
        var summary = Assert.Single(await service.GetByTechnicianAsync(request.TechnicianId!.Value));
        Assert.Null(summary.PropertyTitle);
        Assert.Null(summary.PropertyAddress);
        Assert.Null(summary.PropertyCity);
        Assert.Null(summary.RequesterName);
        var detail = (await service.GetByIdAsync(request.Id))!;
        Assert.Null(detail.RequesterName);
    }

    private static ApplicationDbContext Context() => new(new DbContextOptionsBuilder<ApplicationDbContext>()
        .UseInMemoryDatabase(Guid.NewGuid().ToString()).Options);
}
