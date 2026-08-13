using Microsoft.EntityFrameworkCore;
using RentFlow.Api.Data;
using RentFlow.Api.DTOs.Viewings;
using RentFlow.Api.Models;
using RentFlow.Api.Services;
using Xunit;

namespace RentFlow.Api.Tests.Services;

public class ViewingServiceTests
{
    [Fact]
    public async Task CreateAsync_CreatesPendingViewing_WhenRequestIsValid()
    {
        await using var context = CreateContext();
        var service = new ViewingService(context);
        var tenantId = Guid.NewGuid();
        var propertyId = Guid.NewGuid();
        var requestedDateTime = DateTimeOffset.UtcNow.AddDays(2);

        var result = await service.CreateAsync(tenantId, new CreateViewingRequestDto
        {
            PropertyId = propertyId,
            RequestedDateTime = requestedDateTime,
            TenantMessage = "Please confirm availability."
        });

        Assert.NotEqual(Guid.Empty, result.Id);
        Assert.Equal(tenantId, result.TenantId);
        Assert.Equal(propertyId, result.PropertyId);
        Assert.Equal(requestedDateTime, result.RequestedDateTime);
        Assert.Equal(ViewingStatus.Pending, result.Status);
        Assert.Null(result.UpdatedAt);

        var stored = await context.ViewingRequests.SingleAsync();
        Assert.Equal(ViewingStatus.Pending, stored.Status);
    }

    [Fact]
    public async Task CreateAsync_RejectsViewingInPast()
    {
        await using var context = CreateContext();
        var service = new ViewingService(context);

        var exception = await Assert.ThrowsAsync<ViewingServiceException>(() =>
            service.CreateAsync(Guid.NewGuid(), new CreateViewingRequestDto
            {
                PropertyId = Guid.NewGuid(),
                RequestedDateTime = DateTimeOffset.UtcNow.AddDays(-1)
            }));

        Assert.Equal(ViewingServiceError.Validation, exception.Error);
        Assert.Empty(context.ViewingRequests);
    }

    [Fact]
    public async Task CreateAsync_RejectsDuplicateTenantPropertyAndTime()
    {
        await using var context = CreateContext();
        var service = new ViewingService(context);
        var tenantId = Guid.NewGuid();
        var propertyId = Guid.NewGuid();
        var requestedDateTime = DateTimeOffset.UtcNow.AddDays(3);
        var request = new CreateViewingRequestDto
        {
            PropertyId = propertyId,
            RequestedDateTime = requestedDateTime
        };

        await service.CreateAsync(tenantId, request);

        var exception = await Assert.ThrowsAsync<ViewingServiceException>(() =>
            service.CreateAsync(tenantId, request));

        Assert.Equal(ViewingServiceError.Conflict, exception.Error);
        Assert.Equal(1, await context.ViewingRequests.CountAsync());
    }

    [Fact]
    public async Task ApproveAsync_ChangesPendingViewingToApproved()
    {
        await using var context = CreateContext();
        var viewing = AddViewing(context, status: ViewingStatus.Pending);
        await context.SaveChangesAsync();
        var service = new ViewingService(context);

        var result = await service.ApproveAsync(viewing.Id, "Approved.");

        Assert.Equal(ViewingStatus.Approved, result.Status);
        Assert.Equal("Approved.", result.LandlordResponse);
        Assert.NotNull(result.UpdatedAt);
        Assert.Equal(ViewingStatus.Approved, viewing.Status);
    }

    [Fact]
    public async Task ApproveAsync_RejectsNonPendingViewing()
    {
        await using var context = CreateContext();
        var viewing = AddViewing(context, status: ViewingStatus.Rejected);
        await context.SaveChangesAsync();
        var service = new ViewingService(context);

        var exception = await Assert.ThrowsAsync<ViewingServiceException>(() =>
            service.ApproveAsync(viewing.Id));

        Assert.Equal(ViewingServiceError.Conflict, exception.Error);
        Assert.Equal(ViewingStatus.Rejected, viewing.Status);
    }

    [Fact]
    public async Task RejectAsync_ChangesPendingViewingToRejected_WhenReasonIsSupplied()
    {
        await using var context = CreateContext();
        var viewing = AddViewing(context, status: ViewingStatus.Pending);
        await context.SaveChangesAsync();
        var service = new ViewingService(context);

        var result = await service.RejectAsync(viewing.Id, "  Time is unavailable.  ");

        Assert.Equal(ViewingStatus.Rejected, result.Status);
        Assert.Equal("Time is unavailable.", result.LandlordResponse);
        Assert.NotNull(result.UpdatedAt);
    }

    [Fact]
    public async Task RejectAsync_RejectsBlankReason()
    {
        await using var context = CreateContext();
        var viewing = AddViewing(context, status: ViewingStatus.Pending);
        await context.SaveChangesAsync();
        var service = new ViewingService(context);

        var exception = await Assert.ThrowsAsync<ViewingServiceException>(() =>
            service.RejectAsync(viewing.Id, "   "));

        Assert.Equal(ViewingServiceError.Validation, exception.Error);
        Assert.Equal(ViewingStatus.Pending, viewing.Status);
        Assert.Null(viewing.UpdatedAt);
    }

    [Fact]
    public async Task CancelAsync_AllowsOwnerToCancelFuturePendingViewing()
    {
        await using var context = CreateContext();
        var tenantId = Guid.NewGuid();
        var viewing = AddViewing(
            context,
            tenantId: tenantId,
            requestedDateTime: DateTimeOffset.UtcNow.AddDays(1),
            status: ViewingStatus.Pending);
        await context.SaveChangesAsync();
        var service = new ViewingService(context);

        var result = await service.CancelAsync(viewing.Id, tenantId);

        Assert.Equal(ViewingStatus.Cancelled, result.Status);
        Assert.NotNull(result.UpdatedAt);
    }

    [Fact]
    public async Task CancelAsync_RejectsMismatchedTenant()
    {
        await using var context = CreateContext();
        var viewing = AddViewing(context, tenantId: Guid.NewGuid());
        await context.SaveChangesAsync();
        var service = new ViewingService(context);

        var exception = await Assert.ThrowsAsync<ViewingServiceException>(() =>
            service.CancelAsync(viewing.Id, Guid.NewGuid()));

        Assert.Equal(ViewingServiceError.NotFound, exception.Error);
        Assert.Equal(ViewingStatus.Pending, viewing.Status);
    }

    [Fact]
    public async Task CancelAsync_RejectsViewingWhoseScheduledTimeHasPassed()
    {
        await using var context = CreateContext();
        var tenantId = Guid.NewGuid();
        var viewing = AddViewing(
            context,
            tenantId: tenantId,
            requestedDateTime: DateTimeOffset.UtcNow.AddDays(-1));
        await context.SaveChangesAsync();
        var service = new ViewingService(context);

        var exception = await Assert.ThrowsAsync<ViewingServiceException>(() =>
            service.CancelAsync(viewing.Id, tenantId));

        Assert.Equal(ViewingServiceError.Conflict, exception.Error);
        Assert.Equal(ViewingStatus.Pending, viewing.Status);
    }

    [Fact]
    public async Task GetByTenantAsync_ReturnsOnlyThatTenantsViewings()
    {
        await using var context = CreateContext();
        var tenantId = Guid.NewGuid();
        AddViewing(context, tenantId: tenantId, propertyId: Guid.NewGuid());
        AddViewing(context, tenantId: tenantId, propertyId: Guid.NewGuid());
        AddViewing(context, tenantId: Guid.NewGuid(), propertyId: Guid.NewGuid());
        await context.SaveChangesAsync();
        var service = new ViewingService(context);

        var results = await service.GetByTenantAsync(tenantId);

        Assert.Equal(2, results.Count);
        Assert.All(results, result => Assert.Equal(tenantId, result.TenantId));
    }

    [Fact]
    public async Task GetByPropertyAsync_ReturnsOnlyThatPropertysViewings()
    {
        await using var context = CreateContext();
        var propertyId = Guid.NewGuid();
        AddViewing(context, tenantId: Guid.NewGuid(), propertyId: propertyId);
        AddViewing(context, tenantId: Guid.NewGuid(), propertyId: propertyId);
        AddViewing(context, tenantId: Guid.NewGuid(), propertyId: Guid.NewGuid());
        await context.SaveChangesAsync();
        var service = new ViewingService(context);

        var results = await service.GetByPropertyAsync(propertyId);

        Assert.Equal(2, results.Count);
        Assert.All(results, result => Assert.Equal(propertyId, result.PropertyId));
    }

    private static ApplicationDbContext CreateContext()
    {
        var options = new DbContextOptionsBuilder<ApplicationDbContext>()
            .UseInMemoryDatabase($"ViewingServiceTests-{Guid.NewGuid()}")
            .Options;

        return new ApplicationDbContext(options);
    }

    private static ViewingRequest AddViewing(
        ApplicationDbContext context,
        Guid? tenantId = null,
        Guid? propertyId = null,
        DateTimeOffset? requestedDateTime = null,
        ViewingStatus status = ViewingStatus.Pending)
    {
        var viewing = new ViewingRequest
        {
            Id = Guid.NewGuid(),
            TenantId = tenantId ?? Guid.NewGuid(),
            PropertyId = propertyId ?? Guid.NewGuid(),
            RequestedDateTime = requestedDateTime ?? DateTimeOffset.UtcNow.AddDays(2),
            Status = status,
            CreatedAt = DateTimeOffset.UtcNow
        };

        context.ViewingRequests.Add(viewing);
        return viewing;
    }
}
