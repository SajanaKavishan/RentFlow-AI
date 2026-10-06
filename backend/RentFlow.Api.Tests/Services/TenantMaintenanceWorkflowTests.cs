using Microsoft.EntityFrameworkCore;
using RentFlow.Api.Data;
using RentFlow.Api.DTOs.Maintenance;
using RentFlow.Api.Models;
using RentFlow.Api.Services;
using Xunit;

namespace RentFlow.Api.Tests.Services;

public sealed class TenantMaintenanceWorkflowTests
{
    [Theory]
    [InlineData(LeaseAgreementStatus.Pending)]
    [InlineData(LeaseAgreementStatus.Terminated)]
    [InlineData(LeaseAgreementStatus.Completed)]
    public async Task Create_RejectsNonActiveLease(LeaseAgreementStatus status)
    {
        await using var context = Context();
        var tenant = Guid.NewGuid();
        var request = Request();
        await MaintenanceTenancyFixture.SeedAsync(context, tenant, request.PropertyId, status);
        await AssertForbidden(context, tenant, request);
    }

    [Theory]
    [InlineData("expired")]
    [InlineData("future")]
    [InlineData("other-tenant")]
    [InlineData("other-property")]
    [InlineData("unaccepted-offer")]
    [InlineData("unapproved-application")]
    [InlineData("mismatched-offer-tenant")]
    [InlineData("mismatched-application-property")]
    public async Task Create_RejectsInvalidRentalChain(string invalid)
    {
        await using var context = Context();
        var tenant = Guid.NewGuid();
        var request = Request();
        var lease = await MaintenanceTenancyFixture.SeedAsync(context, tenant, request.PropertyId);
        var today = DateOnly.FromDateTime(DateTime.UtcNow);
        switch (invalid)
        {
            case "expired": lease.EndDate = today.AddDays(-1); break;
            case "future": lease.StartDate = today.AddDays(1); break;
            case "other-tenant": lease.TenantId = Guid.NewGuid(); break;
            case "other-property": request.PropertyId = Guid.NewGuid(); break;
            case "unaccepted-offer": lease.RentalOffer.Status = RentalOfferStatus.Pending; break;
            case "unapproved-application": lease.RentalOffer.RentalApplication.Status = RentalApplicationStatus.Submitted; break;
            case "mismatched-offer-tenant": lease.RentalOffer.TenantId = Guid.NewGuid(); break;
            case "mismatched-application-property": lease.RentalOffer.RentalApplication.PropertyId = Guid.NewGuid(); break;
        }
        await context.SaveChangesAsync();
        await AssertForbidden(context, tenant, request);
    }

    [Fact]
    public async Task Create_RejectsNoLeaseEvenWithApprovedApplication()
    {
        await using var context = Context();
        var tenant = Guid.NewGuid();
        var request = Request();
        context.RentalApplications.Add(new RentalApplication { TenantId = tenant, PropertyId = request.PropertyId, Status = RentalApplicationStatus.Approved });
        await context.SaveChangesAsync();
        await AssertForbidden(context, tenant, request);
    }

    [Theory]
    [InlineData(null)]
    [InlineData((PreferredAccessWindow)99)]
    public async Task Create_RequiresDefinedAccessWindow(PreferredAccessWindow? window)
    {
        await using var context = Context();
        var request = Request();
        request.PreferredAccessWindow = window;
        var error = await Assert.ThrowsAsync<MaintenanceRequestServiceException>(() => new MaintenanceRequestService(context).CreateAsync(Guid.NewGuid(), request));
        Assert.Equal(MaintenanceRequestServiceError.Validation, error.Error);
        Assert.Empty(context.MaintenanceRequests);
    }

    [Theory]
    [InlineData(MaintenanceCategory.Hvac)]
    [InlineData(MaintenanceCategory.LocksDoors)]
    [InlineData(MaintenanceCategory.Security)]
    public async Task Create_PreservesCategoriesAndLegacyPriority(MaintenanceCategory category)
    {
        await using var context = Context();
        var tenant = Guid.NewGuid();
        var request = Request();
        request.Category = category;
        request.Priority = MaintenancePriority.Low;
        await MaintenanceTenancyFixture.SeedAsync(context, tenant, request.PropertyId);
        var result = await new MaintenanceRequestService(context).CreateAsync(tenant, request);
        Assert.Equal(category, result.Category);
        Assert.Equal(MaintenancePriority.Low, result.Priority);
        Assert.Equal(PreferredAccessWindow.Morning, result.PreferredAccessWindow);
    }

    [Fact]
    public async Task Create_DerivesTitleAndPreservesLongDescriptionAndLegacyNotes()
    {
        await using var context = Context();
        var tenant = Guid.NewGuid();
        var request = Request();
        request.Description = "  The   kitchen\n tap is leaking. " + new string('x', 2500);
        request.TenantAccessNotes = " Please knock. ";
        await MaintenanceTenancyFixture.SeedAsync(context, tenant, request.PropertyId);
        context.Properties.Local.Single(property => property.Id == request.PropertyId).Title = "Port city residence";
        await context.SaveChangesAsync();
        var service = new MaintenanceRequestService(context);
        var result = await service.CreateAsync(tenant, request);
        Assert.Equal("The kitchen tap is leaking", result.Title);
        Assert.Equal(request.Description.Trim(), result.Description);
        Assert.Equal("Please knock.", result.TenantAccessNotes);
        Assert.Matches("^MR-[A-F0-9]{16}$", result.ReferenceCode);
        Assert.DoesNotContain(result.Id.ToString(), result.ReferenceCode);
        Assert.Equal(result.ReferenceCode, (await service.GetByIdAsync(result.Id))!.ReferenceCode);
        Assert.Equal(result.ReferenceCode, (await service.GetByTenantAsync(tenant)).Single().ReferenceCode);
        Assert.Equal("Port city residence", result.PropertyTitle);
        Assert.Equal(result.PropertyTitle, (await service.GetByIdAsync(result.Id))!.PropertyTitle);
        Assert.Equal(result.PropertyTitle, (await service.GetByTenantAsync(tenant)).Single().PropertyTitle);
    }

    [Fact]
    public async Task Create_PreservesSuppliedLegacyTitleAndCapsDerivedTitle()
    {
        await using var context = Context();
        var tenant = Guid.NewGuid();
        var request = Request();
        request.Title = " Custom legacy title ";
        await MaintenanceTenancyFixture.SeedAsync(context, tenant, request.PropertyId);
        var service = new MaintenanceRequestService(context);
        Assert.Equal("Custom legacy title", (await service.CreateAsync(tenant, request)).Title);
        request.Title = null;
        request.Description = string.Join(' ', Enumerable.Repeat("dripping", 60));
        var result = await service.CreateAsync(tenant, request);
        Assert.InRange(result.Title.Length, 1, 200);
        Assert.Equal(request.Description, result.Description);
    }

    [Fact]
    public async Task Create_NeverDerivesAnEmptyTitleFromNonblankDescription()
    {
        await using var context = Context();
        var tenant = Guid.NewGuid();
        var input = Request();
        await MaintenanceTenancyFixture.SeedAsync(context, tenant, input.PropertyId);
        var service = new MaintenanceRequestService(context);
        foreach (var description in new[] { ".", "...", "  !  " })
        {
            input.Description = description;
            var created = await service.CreateAsync(tenant, input);
            Assert.Equal("Plumbing issue", created.Title);
            Assert.Equal(description.Trim(), created.Description);
        }
    }

    [Fact]
    public async Task LegacyRequestRemainsReadableWithoutAccessWindow()
    {
        await using var context = Context();
        var request = new MaintenanceRequest { TenantId = Guid.NewGuid(), PropertyId = Guid.NewGuid(), Title = "Legacy", Description = "Legacy description", Priority = MaintenancePriority.Low };
        context.MaintenanceRequests.Add(request);
        await context.SaveChangesAsync();
        var result = await new MaintenanceRequestService(context).GetByIdAsync(request.Id);
        Assert.Null(result!.PreferredAccessWindow);
        Assert.Equal(MaintenancePriority.Low, result.Priority);
        Assert.Matches("^MR-[A-F0-9]{16}$", result.ReferenceCode);
    }

    private static async Task AssertForbidden(ApplicationDbContext context, Guid tenant, CreateMaintenanceRequestDto request)
    {
        var error = await Assert.ThrowsAsync<MaintenanceRequestServiceException>(() => new MaintenanceRequestService(context).CreateAsync(tenant, request));
        Assert.Equal(MaintenanceRequestServiceError.Forbidden, error.Error);
        Assert.Empty(context.MaintenanceRequests);
        Assert.Empty(context.MaintenanceStatusHistories);
    }

    internal static CreateMaintenanceRequestDto Request() => new() { PropertyId = Guid.NewGuid(), Description = "The kitchen tap is leaking.", Category = MaintenanceCategory.Plumbing, Priority = MaintenancePriority.Normal, PreferredAccessWindow = PreferredAccessWindow.Morning };

    private static ApplicationDbContext Context() => new(new DbContextOptionsBuilder<ApplicationDbContext>().UseInMemoryDatabase($"maintenance-task2-{Guid.NewGuid()}").Options);
}
