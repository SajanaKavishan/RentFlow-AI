using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;
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
        var requestedDateTime = new DateTimeOffset(DateTime.UtcNow.Date.AddDays(2).AddHours(3.5));
        context.Properties.Add(CreateProperty(propertyId));
        AddSchedule(context, propertyId);
        await context.SaveChangesAsync();

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
        var requestedDateTime = new DateTimeOffset(DateTime.UtcNow.Date.AddDays(3).AddHours(3.5));
        context.Properties.Add(CreateProperty(propertyId));
        AddSchedule(context, propertyId);
        await context.SaveChangesAsync();
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
    public async Task CreateAsync_DoesNotPersistViewingOrNotification_WhenSaveFails()
    {
        var saveInterceptor = new FailingSaveChangesInterceptor();
        await using var context = CreateContext(saveInterceptor);
        var property = CreateProperty(Guid.NewGuid());
        context.Properties.Add(property);
        AddSchedule(context, property.Id);
        await context.SaveChangesAsync();
        var service = new ViewingService(context);
        saveInterceptor.ShouldFail = true;

        await Assert.ThrowsAsync<DbUpdateException>(() =>
            service.CreateAsync(Guid.NewGuid(), new CreateViewingRequestDto
            {
                PropertyId = property.Id,
                RequestedDateTime = new DateTimeOffset(DateTime.UtcNow.Date.AddDays(2).AddHours(3.5))
            }));

        saveInterceptor.ShouldFail = false;
        context.ChangeTracker.Clear();
        Assert.Empty(await context.ViewingRequests.ToListAsync());
        Assert.Empty(await context.Notifications.ToListAsync());
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
    public async Task ApproveAsync_DoesNotPersistViewingOrNotification_WhenSaveFails()
    {
        var saveInterceptor = new FailingSaveChangesInterceptor();
        await using var context = CreateContext(saveInterceptor);
        var viewing = AddViewing(context, status: ViewingStatus.Pending);
        await context.SaveChangesAsync();
        var service = new ViewingService(context);
        saveInterceptor.ShouldFail = true;

        await Assert.ThrowsAsync<DbUpdateException>(() =>
            service.ApproveAsync(viewing.Id, "Approved."));

        saveInterceptor.ShouldFail = false;
        context.ChangeTracker.Clear();
        var storedViewing = await context.ViewingRequests.SingleAsync();
        Assert.Equal(ViewingStatus.Pending, storedViewing.Status);
        Assert.Empty(await context.Notifications.ToListAsync());
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

    private static ApplicationDbContext CreateContext(
        SaveChangesInterceptor? saveChangesInterceptor = null)
    {
        var optionsBuilder = new DbContextOptionsBuilder<ApplicationDbContext>()
            .UseInMemoryDatabase($"ViewingServiceTests-{Guid.NewGuid()}");

        if (saveChangesInterceptor is not null)
        {
            optionsBuilder.AddInterceptors(saveChangesInterceptor);
        }

        return new ApplicationDbContext(optionsBuilder.Options);
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

        if (!context.Properties.Local.Any(property => property.Id == viewing.PropertyId))
        {
            context.Properties.Add(new Property
            {
                Id = viewing.PropertyId,
                LandlordId = Guid.NewGuid(),
                Title = "Viewing test property",
                Description = "Property used by viewing service tests.",
                Address = "1 Test Street",
                City = "Colombo",
                MonthlyRent = 100000m,
                Bedrooms = 2,
                Bathrooms = 1,
                CreatedAt = DateTimeOffset.UtcNow
            });
        }

        context.ViewingRequests.Add(viewing);
        return viewing;
    }

    private static void AddSchedule(ApplicationDbContext context, Guid id)
    {
        context.PropertyViewingAvailabilities.AddRange(Enumerable.Range(0, 7).Select(day =>
            new PropertyViewingAvailability { PropertyId = id, DayOfWeek = day, IsEnabled = true,
                StartTime = new TimeOnly(9, 0), EndTime = new TimeOnly(17, 0) }));
    }

    private static Property CreateProperty(Guid propertyId) => new()
    {
        Id = propertyId,
        LandlordId = Guid.NewGuid(),
        Title = "Viewing test property",
        Description = "Property used by viewing service tests.",
        Address = "1 Test Street",
        City = "Colombo",
        MonthlyRent = 100000m,
        Bedrooms = 2,
        Bathrooms = 1,
        CreatedAt = DateTimeOffset.UtcNow
    };

    private sealed class FailingSaveChangesInterceptor : SaveChangesInterceptor
    {
        public bool ShouldFail { get; set; }

        public override ValueTask<InterceptionResult<int>> SavingChangesAsync(
            DbContextEventData eventData,
            InterceptionResult<int> result,
            CancellationToken cancellationToken = default)
        {
            if (ShouldFail)
            {
                throw new DbUpdateException("Simulated decision persistence failure.");
            }

            return base.SavingChangesAsync(eventData, result, cancellationToken);
        }
    }
}
