using Microsoft.EntityFrameworkCore;
using RentFlow.Api.Data;
using RentFlow.Api.DTOs.Maintenance;
using RentFlow.Api.Models;
using RentFlow.Api.Services;
using Xunit;

namespace RentFlow.Api.Tests.Services;

public class MaintenanceRequestServiceTests
{
    [Fact]
    public async Task CreateAsync_CreatesSubmittedRequest_WhenRequestIsValid()
    {
        await using var context = CreateContext();
        var service = new MaintenanceRequestService(context);
        var tenantId = Guid.NewGuid();
        var request = CreateValidRequest();

        var result = await service.CreateAsync(tenantId, request);

        Assert.NotEqual(Guid.Empty, result.Id);
        Assert.Equal(tenantId, result.TenantId);
        Assert.Equal(request.PropertyId, result.PropertyId);
        Assert.Equal("Leaking kitchen tap", result.Title);
        Assert.Equal(MaintenanceRequestStatus.Submitted, result.Status);
        Assert.Equal(TimeSpan.Zero, result.CreatedAt.Offset);
        Assert.Null(result.UpdatedAt);
        Assert.Equal(result.Id, (await context.MaintenanceRequests.SingleAsync()).Id);
    }

    [Fact]
    public async Task CreateAsync_RejectsEmptyPropertyId()
    {
        await using var context = CreateContext();
        var request = CreateValidRequest();
        request.PropertyId = Guid.Empty;

        var exception = await Assert.ThrowsAsync<MaintenanceRequestServiceException>(() =>
            new MaintenanceRequestService(context).CreateAsync(Guid.NewGuid(), request));

        Assert.Equal(MaintenanceRequestServiceError.Validation, exception.Error);
        Assert.Empty(context.MaintenanceRequests);
    }

    [Fact]
    public async Task CreateAsync_RejectsEmptyTenantId()
    {
        await using var context = CreateContext();

        var exception = await Assert.ThrowsAsync<MaintenanceRequestServiceException>(() =>
            new MaintenanceRequestService(context).CreateAsync(Guid.Empty, CreateValidRequest()));

        Assert.Equal(MaintenanceRequestServiceError.Validation, exception.Error);
    }

    [Fact]
    public async Task CreateAsync_RejectsBlankTitle()
    {
        await using var context = CreateContext();
        var request = CreateValidRequest();
        request.Title = "   ";

        var exception = await Assert.ThrowsAsync<MaintenanceRequestServiceException>(() =>
            new MaintenanceRequestService(context).CreateAsync(Guid.NewGuid(), request));

        Assert.Equal(MaintenanceRequestServiceError.Validation, exception.Error);
    }

    [Fact]
    public async Task CreateAsync_RejectsTitleLongerThan200Characters()
    {
        await using var context = CreateContext();
        var request = CreateValidRequest();
        request.Title = new string('A', 201);

        var exception = await Assert.ThrowsAsync<MaintenanceRequestServiceException>(() =>
            new MaintenanceRequestService(context).CreateAsync(Guid.NewGuid(), request));

        Assert.Equal(MaintenanceRequestServiceError.Validation, exception.Error);
    }

    [Fact]
    public async Task CreateAsync_RejectsDescriptionLongerThan4000Characters()
    {
        await using var context = CreateContext();
        var request = CreateValidRequest();
        request.Description = new string('A', 4001);

        var exception = await Assert.ThrowsAsync<MaintenanceRequestServiceException>(() =>
            new MaintenanceRequestService(context).CreateAsync(Guid.NewGuid(), request));

        Assert.Equal(MaintenanceRequestServiceError.Validation, exception.Error);
    }

    [Fact]
    public async Task UpdateTenantRequestAsync_AllowsTenantToUpdateOwnSubmittedRequest()
    {
        await using var context = CreateContext();
        var tenantId = Guid.NewGuid();
        var maintenanceRequest = AddRequest(context, tenantId: tenantId);
        await context.SaveChangesAsync();
        var update = new UpdateMaintenanceRequestDto
        {
            Title = "  Water leak under the sink  ",
            Description = "  The leak has become more frequent.  ",
            Category = MaintenanceCategory.Plumbing,
            Priority = MaintenancePriority.High,
            TenantAccessNotes = "  Call before visiting.  "
        };

        var result = await new MaintenanceRequestService(context)
            .UpdateTenantRequestAsync(maintenanceRequest.Id, tenantId, update);

        Assert.Equal("Water leak under the sink", result.Title);
        Assert.Equal("The leak has become more frequent.", result.Description);
        Assert.Equal(MaintenancePriority.High, result.Priority);
        Assert.Equal("Call before visiting.", result.TenantAccessNotes);
        Assert.NotNull(result.UpdatedAt);
    }

    [Fact]
    public async Task UpdateTenantRequestAsync_RejectsAnotherTenantsRequest()
    {
        await using var context = CreateContext();
        var maintenanceRequest = AddRequest(context, tenantId: Guid.NewGuid());
        await context.SaveChangesAsync();

        var exception = await Assert.ThrowsAsync<MaintenanceRequestServiceException>(() =>
            new MaintenanceRequestService(context).UpdateTenantRequestAsync(
                maintenanceRequest.Id,
                Guid.NewGuid(),
                CreateValidUpdate()));

        Assert.Equal(MaintenanceRequestServiceError.NotFound, exception.Error);
    }

    [Theory]
    [InlineData(MaintenanceRequestStatus.Triaged)]
    [InlineData(MaintenanceRequestStatus.Completed)]
    [InlineData(MaintenanceRequestStatus.Cancelled)]
    public async Task UpdateTenantRequestAsync_RejectsNonSubmittedRequest(
        MaintenanceRequestStatus status)
    {
        await using var context = CreateContext();
        var tenantId = Guid.NewGuid();
        var maintenanceRequest = AddRequest(context, tenantId: tenantId, status: status);
        await context.SaveChangesAsync();

        var exception = await Assert.ThrowsAsync<MaintenanceRequestServiceException>(() =>
            new MaintenanceRequestService(context).UpdateTenantRequestAsync(
                maintenanceRequest.Id,
                tenantId,
                CreateValidUpdate()));

        Assert.Equal(MaintenanceRequestServiceError.Conflict, exception.Error);
    }

    [Fact]
    public async Task TriageAsync_ChangesSubmittedRequestToTriaged()
    {
        await using var context = CreateContext();
        var maintenanceRequest = AddRequest(context);
        await context.SaveChangesAsync();

        var result = await new MaintenanceRequestService(context).TriageAsync(
            maintenanceRequest.Id,
            new TriageMaintenanceRequestDto
            {
                Category = MaintenanceCategory.Electrical,
                Priority = MaintenancePriority.Emergency,
                TriageNotes = "  Isolate the circuit immediately.  "
            });

        Assert.Equal(MaintenanceRequestStatus.Triaged, result.Status);
        Assert.Equal(MaintenanceCategory.Electrical, result.Category);
        Assert.Equal(MaintenancePriority.Emergency, result.Priority);
        Assert.Equal("Isolate the circuit immediately.", result.TriageNotes);
        Assert.NotNull(result.UpdatedAt);
    }

    [Fact]
    public async Task TriageAsync_RejectsRequestOutsideSubmittedState()
    {
        await using var context = CreateContext();
        var maintenanceRequest = AddRequest(context, status: MaintenanceRequestStatus.Assigned);
        await context.SaveChangesAsync();

        var exception = await Assert.ThrowsAsync<MaintenanceRequestServiceException>(() =>
            new MaintenanceRequestService(context).TriageAsync(
                maintenanceRequest.Id,
                new TriageMaintenanceRequestDto
                {
                    Category = MaintenanceCategory.Plumbing,
                    Priority = MaintenancePriority.Normal
                }));

        Assert.Equal(MaintenanceRequestServiceError.Conflict, exception.Error);
    }

    [Fact]
    public async Task AssignTechnicianAsync_AssignsTechnicianToTriagedRequest()
    {
        await using var context = CreateContext();
        var maintenanceRequest = AddRequest(context, status: MaintenanceRequestStatus.Triaged);
        await context.SaveChangesAsync();
        var technicianId = Guid.NewGuid();

        var result = await new MaintenanceRequestService(context).AssignTechnicianAsync(
            maintenanceRequest.Id,
            new AssignTechnicianDto
            {
                TechnicianId = technicianId,
                AssignmentNotes = "  Bring replacement fittings.  "
            });

        Assert.Equal(MaintenanceRequestStatus.Assigned, result.Status);
        Assert.Equal(technicianId, result.TechnicianId);
        Assert.Equal("Bring replacement fittings.", result.AssignmentNotes);
        Assert.NotNull(result.UpdatedAt);
    }

    [Fact]
    public async Task AssignTechnicianAsync_RejectsEmptyTechnicianId()
    {
        await using var context = CreateContext();
        var maintenanceRequest = AddRequest(context, status: MaintenanceRequestStatus.Triaged);
        await context.SaveChangesAsync();

        var exception = await Assert.ThrowsAsync<MaintenanceRequestServiceException>(() =>
            new MaintenanceRequestService(context).AssignTechnicianAsync(
                maintenanceRequest.Id,
                new AssignTechnicianDto()));

        Assert.Equal(MaintenanceRequestServiceError.Validation, exception.Error);
    }

    [Theory]
    [InlineData(MaintenanceRequestStatus.Submitted)]
    [InlineData(MaintenanceRequestStatus.Completed)]
    [InlineData(MaintenanceRequestStatus.Cancelled)]
    public async Task AssignTechnicianAsync_RejectsRequestOutsideTriagedState(
        MaintenanceRequestStatus status)
    {
        await using var context = CreateContext();
        var maintenanceRequest = AddRequest(context, status: status);
        await context.SaveChangesAsync();

        var exception = await Assert.ThrowsAsync<MaintenanceRequestServiceException>(() =>
            new MaintenanceRequestService(context).AssignTechnicianAsync(
                maintenanceRequest.Id,
                new AssignTechnicianDto { TechnicianId = Guid.NewGuid() }));

        Assert.Equal(MaintenanceRequestServiceError.Conflict, exception.Error);
    }

    private static ApplicationDbContext CreateContext()
    {
        var options = new DbContextOptionsBuilder<ApplicationDbContext>()
            .UseInMemoryDatabase($"MaintenanceRequestServiceTests-{Guid.NewGuid()}")
            .Options;

        return new ApplicationDbContext(options);
    }

    private static CreateMaintenanceRequestDto CreateValidRequest() =>
        new()
        {
            PropertyId = Guid.NewGuid(),
            Title = "Leaking kitchen tap",
            Description = "Water is leaking from the kitchen tap whenever it is used.",
            Category = MaintenanceCategory.Plumbing,
            Priority = MaintenancePriority.Normal,
            TenantAccessNotes = "Please call before arriving."
        };

    private static UpdateMaintenanceRequestDto CreateValidUpdate() =>
        new()
        {
            Title = "Updated kitchen tap leak",
            Description = "The kitchen tap continues to leak.",
            Category = MaintenanceCategory.Plumbing,
            Priority = MaintenancePriority.Normal,
            TenantAccessNotes = "Please call before arriving."
        };

    private static MaintenanceRequest AddRequest(
        ApplicationDbContext context,
        Guid? tenantId = null,
        Guid? propertyId = null,
        MaintenanceRequestStatus status = MaintenanceRequestStatus.Submitted)
    {
        var maintenanceRequest = new MaintenanceRequest
        {
            Id = Guid.NewGuid(),
            TenantId = tenantId ?? Guid.NewGuid(),
            PropertyId = propertyId ?? Guid.NewGuid(),
            Title = "Leaking kitchen tap",
            Description = "Water is leaking from the kitchen tap.",
            Category = MaintenanceCategory.Plumbing,
            Priority = MaintenancePriority.Normal,
            Status = status,
            CreatedAt = DateTimeOffset.UtcNow
        };

        context.MaintenanceRequests.Add(maintenanceRequest);
        return maintenanceRequest;
    }
}
