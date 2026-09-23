using Microsoft.EntityFrameworkCore;
using RentFlow.Api.Data;
using RentFlow.Api.DTOs.RentalOffers;
using RentFlow.Api.Models;
using RentFlow.Api.Services;
using Xunit;

namespace RentFlow.Api.Tests.Services;

public class RentalOfferServiceTests
{
    [Fact]
    public async Task CreateAsync_CreatesPendingOffer_WhenApplicationIsApproved()
    {
        await using var context = CreateContext();

        var application = AddRentalApplication(
            context,
            status: RentalApplicationStatus.Approved);

        await context.SaveChangesAsync();

        var service = CreateService(context);

        var request = new CreateRentalOfferDto
        {
            RentalApplicationId = application.Id,
            MonthlyRent = 85000m,
            SecurityDeposit = 170000m,
            ProposedStartDate = DateOnly.FromDateTime(DateTime.UtcNow.AddDays(30)),
            ProposedEndDate = DateOnly.FromDateTime(DateTime.UtcNow.AddMonths(12)),
            ExpiresAt = DateTimeOffset.UtcNow.AddDays(7),
            LandlordNote = "Offer for approved application."
        };

        var result = await service.CreateAsync(request);

        Assert.NotEqual(Guid.Empty, result.Id);
        Assert.Equal(application.Id, result.RentalApplicationId);
        Assert.Equal(application.TenantId, result.TenantId);
        Assert.Equal(application.PropertyId, result.PropertyId);
        Assert.Equal(85000m, result.MonthlyRent);
        Assert.Equal(170000m, result.SecurityDeposit);
        Assert.Equal(RentalOfferStatus.Pending, result.Status);

        var storedOffer = await context.RentalOffers.SingleAsync();

        Assert.Equal(result.Id, storedOffer.Id);
        Assert.Equal(RentalOfferStatus.Pending, storedOffer.Status);
    }

    [Fact]
    public async Task CreateAsync_RejectsApplication_WhenApplicationIsNotApproved()
    {
        await using var context = CreateContext();

        var application = AddRentalApplication(
            context,
            status: RentalApplicationStatus.UnderReview);

        await context.SaveChangesAsync();

        var service = CreateService(context);

        var request = new CreateRentalOfferDto
        {
            RentalApplicationId = application.Id,
            MonthlyRent = 85000m,
            SecurityDeposit = 170000m,
            ProposedStartDate = DateOnly.FromDateTime(DateTime.UtcNow.AddDays(30)),
            ProposedEndDate = DateOnly.FromDateTime(DateTime.UtcNow.AddMonths(12)),
            ExpiresAt = DateTimeOffset.UtcNow.AddDays(7)
        };

        var exception = await Assert.ThrowsAsync<RentalOfferServiceException>(() =>
            service.CreateAsync(request));

        Assert.Equal(RentalOfferServiceError.Conflict, exception.Error);
        Assert.Empty(context.RentalOffers);
    }

    [Fact]
    public async Task CreateAsync_RejectsApprovedApplication_WhenPropertyDoesNotExist()
    {
        await using var context = CreateContext();
        var application = new RentalApplication
        {
            TenantId = Guid.NewGuid(),
            PropertyId = Guid.NewGuid(),
            MoveInDate = DateOnly.FromDateTime(DateTime.UtcNow.AddDays(30)),
            MonthlyIncome = 250000m,
            Occupation = "Software Engineer",
            NumberOfOccupants = 2,
            Status = RentalApplicationStatus.Approved
        };
        context.RentalApplications.Add(application);
        await context.SaveChangesAsync();

        var service = CreateService(context);
        var request = new CreateRentalOfferDto
        {
            RentalApplicationId = application.Id,
            MonthlyRent = 85000m,
            SecurityDeposit = 170000m,
            ProposedStartDate = DateOnly.FromDateTime(DateTime.UtcNow.AddDays(30)),
            ProposedEndDate = DateOnly.FromDateTime(DateTime.UtcNow.AddMonths(12)),
            ExpiresAt = DateTimeOffset.UtcNow.AddDays(7)
        };

        var exception = await Assert.ThrowsAsync<RentalOfferServiceException>(() =>
            service.CreateAsync(request));

        Assert.Equal(RentalOfferServiceError.NotFound, exception.Error);
        Assert.Empty(context.RentalOffers);
    }

    [Fact]
    public async Task CreateAsync_RejectsDuplicatePendingOffer_ForSameApplication()
    {
        await using var context = CreateContext();

        var application = AddRentalApplication(
            context,
            status: RentalApplicationStatus.Approved);

        context.RentalOffers.Add(new RentalOffer
        {
            RentalApplicationId = application.Id,
            TenantId = application.TenantId,
            PropertyId = application.PropertyId,
            MonthlyRent = 80000m,
            SecurityDeposit = 160000m,
            ProposedStartDate = DateOnly.FromDateTime(DateTime.UtcNow.AddDays(20)),
            ProposedEndDate = DateOnly.FromDateTime(DateTime.UtcNow.AddMonths(12)),
            ExpiresAt = DateTimeOffset.UtcNow.AddDays(5),
            Status = RentalOfferStatus.Pending,
            CreatedAt = DateTimeOffset.UtcNow
        });

        await context.SaveChangesAsync();

        var service = CreateService(context);

        var request = new CreateRentalOfferDto
        {
            RentalApplicationId = application.Id,
            MonthlyRent = 85000m,
            SecurityDeposit = 170000m,
            ProposedStartDate = DateOnly.FromDateTime(DateTime.UtcNow.AddDays(30)),
            ProposedEndDate = DateOnly.FromDateTime(DateTime.UtcNow.AddMonths(12)),
            ExpiresAt = DateTimeOffset.UtcNow.AddDays(7)
        };

        var exception = await Assert.ThrowsAsync<RentalOfferServiceException>(() =>
            service.CreateAsync(request));

        Assert.Equal(RentalOfferServiceError.Conflict, exception.Error);
        Assert.Single(context.RentalOffers);
    }

    [Fact]
    public async Task AcceptAsync_AcceptsPendingOffer_WhenTenantMatches()
    {
        await using var context = CreateContext();

        var tenantId = Guid.NewGuid();

        var offer = AddRentalOffer(
            context,
            tenantId,
            RentalOfferStatus.Pending,
            DateTimeOffset.UtcNow.AddDays(5));

        await context.SaveChangesAsync();

        var service = CreateService(context);

        var result = await service.AcceptAsync(
            offer.Id,
            tenantId);

        Assert.Equal(RentalOfferStatus.Accepted, result.Status);
        Assert.NotNull(result.UpdatedAt);
    }

    [Fact]
    public async Task AcceptAsync_RejectsOffer_WhenTenantDoesNotMatch()
    {
        await using var context = CreateContext();

        var offer = AddRentalOffer(
            context,
            Guid.NewGuid(),
            RentalOfferStatus.Pending,
            DateTimeOffset.UtcNow.AddDays(5));

        await context.SaveChangesAsync();

        var service = CreateService(context);

        var exception = await Assert.ThrowsAsync<RentalOfferServiceException>(() =>
            service.AcceptAsync(
                offer.Id,
                Guid.NewGuid()));

        Assert.Equal(RentalOfferServiceError.Conflict, exception.Error);
        Assert.Equal(RentalOfferStatus.Pending, offer.Status);
    }

    [Fact]
    public async Task AcceptAsync_MarksOfferExpired_WhenExpiryHasPassed()
    {
        await using var context = CreateContext();

        var tenantId = Guid.NewGuid();

        var offer = AddRentalOffer(
            context,
            tenantId,
            RentalOfferStatus.Pending,
            DateTimeOffset.UtcNow.AddMinutes(-5));

        await context.SaveChangesAsync();

        var service = CreateService(context);

        var exception = await Assert.ThrowsAsync<RentalOfferServiceException>(() =>
            service.AcceptAsync(
                offer.Id,
                tenantId));

        Assert.Equal(RentalOfferServiceError.Conflict, exception.Error);
        Assert.Equal(RentalOfferStatus.Expired, offer.Status);
    }

    [Fact]
    public async Task RejectAsync_RejectsPendingOffer_WhenTenantMatches()
    {
        await using var context = CreateContext();

        var tenantId = Guid.NewGuid();

        var offer = AddRentalOffer(
            context,
            tenantId,
            RentalOfferStatus.Pending,
            DateTimeOffset.UtcNow.AddDays(5));

        await context.SaveChangesAsync();

        var service = CreateService(context);

        var result = await service.RejectAsync(
            offer.Id,
            tenantId);

        Assert.Equal(RentalOfferStatus.Rejected, result.Status);
        Assert.NotNull(result.UpdatedAt);
    }

    [Fact]
    public async Task WithdrawAsync_WithdrawsPendingOffer()
    {
        await using var context = CreateContext();

        var offer = AddRentalOffer(
            context,
            Guid.NewGuid(),
            RentalOfferStatus.Pending,
            DateTimeOffset.UtcNow.AddDays(5));

        await context.SaveChangesAsync();

        var service = CreateService(context);

        var result = await service.WithdrawAsync(offer.Id);

        Assert.Equal(RentalOfferStatus.Withdrawn, result.Status);
        Assert.NotNull(result.UpdatedAt);
    }

    [Fact]
    public async Task CreateAsync_ExpiresOldPendingOfferAndCreatesReplacement()
    {
        await using var context = CreateContext();
        var now = new DateTimeOffset(2026, 9, 20, 12, 0, 0, TimeSpan.Zero);
        var application = AddRentalApplication(context, RentalApplicationStatus.Approved);
        var oldOffer = AddRentalOffer(
            context, application.TenantId, RentalOfferStatus.Pending, now.AddTicks(-1));
        oldOffer.RentalApplicationId = application.Id;
        oldOffer.PropertyId = application.PropertyId;
        await context.SaveChangesAsync();

        var result = await CreateService(context, now)
            .CreateAsync(CreateOfferRequest(application.Id, now));

        Assert.Equal(RentalOfferStatus.Pending, result.Status);
        Assert.Equal(RentalOfferStatus.Expired, oldOffer.Status);
        Assert.Equal(now, oldOffer.UpdatedAt);
        Assert.Equal(2, await context.RentalOffers.CountAsync());
    }

    [Fact]
    public async Task CreateAsync_ExpiresOfferAtExactBoundaryAndAllowsReplacement()
    {
        await using var context = CreateContext();
        var now = new DateTimeOffset(2026, 9, 20, 12, 0, 0, TimeSpan.Zero);
        var application = AddRentalApplication(context, RentalApplicationStatus.Approved);
        var oldOffer = AddRentalOffer(
            context, application.TenantId, RentalOfferStatus.Pending, now);
        oldOffer.RentalApplicationId = application.Id;
        oldOffer.PropertyId = application.PropertyId;
        await context.SaveChangesAsync();

        var result = await CreateService(context, now)
            .CreateAsync(CreateOfferRequest(application.Id, now));

        Assert.Equal(RentalOfferStatus.Pending, result.Status);
        Assert.Equal(RentalOfferStatus.Expired, oldOffer.Status);
    }

    [Fact]
    public async Task GetByTenantAsync_ExpiresOnlyOwnPendingOffersAndIsIdempotent()
    {
        await using var context = CreateContext();
        var now = new DateTimeOffset(2026, 9, 20, 12, 0, 0, TimeSpan.Zero);
        var tenantId = Guid.NewGuid();
        var expired = AddRentalOffer(context, tenantId, RentalOfferStatus.Pending, now);
        var alreadyExpired = AddRentalOffer(context, tenantId, RentalOfferStatus.Expired, now);
        var accepted = AddRentalOffer(context, tenantId, RentalOfferStatus.Accepted, now);
        var rejected = AddRentalOffer(context, tenantId, RentalOfferStatus.Rejected, now);
        var withdrawn = AddRentalOffer(context, tenantId, RentalOfferStatus.Withdrawn, now);
        var otherTenant = AddRentalOffer(context, Guid.NewGuid(), RentalOfferStatus.Pending, now);
        await context.SaveChangesAsync();

        var service = CreateService(context, now);
        var first = await service.GetByTenantAsync(tenantId);
        var updatedAt = expired.UpdatedAt;
        var second = await service.GetByTenantAsync(tenantId);

        Assert.Equal(RentalOfferStatus.Expired, first.Single(item => item.Id == expired.Id).Status);
        Assert.Equal(RentalOfferStatus.Expired, second.Single(item => item.Id == expired.Id).Status);
        Assert.Equal(now, updatedAt);
        Assert.Equal(updatedAt, expired.UpdatedAt);
        Assert.Equal(RentalOfferStatus.Expired, alreadyExpired.Status);
        Assert.Equal(RentalOfferStatus.Accepted, accepted.Status);
        Assert.Equal(RentalOfferStatus.Rejected, rejected.Status);
        Assert.Equal(RentalOfferStatus.Withdrawn, withdrawn.Status);
        Assert.Equal(RentalOfferStatus.Pending, otherTenant.Status);
        Assert.DoesNotContain(first, item => item.Id == otherTenant.Id);
    }

    [Fact]
    public async Task RefreshExpiredByIdAsync_ReturnsExpiredStatus()
    {
        await using var context = CreateContext();
        var now = new DateTimeOffset(2026, 9, 20, 12, 0, 0, TimeSpan.Zero);
        var offer = AddRentalOffer(
            context, Guid.NewGuid(), RentalOfferStatus.Pending, now.AddTicks(-1));
        await context.SaveChangesAsync();

        var refreshed = await CreateService(context, now).RefreshExpiredByIdAsync(offer.Id);

        Assert.Equal(RentalOfferStatus.Expired, refreshed?.Status);
        Assert.Equal(RentalOfferStatus.Expired, offer.Status);
    }

    [Theory]
    [InlineData(true)]
    [InlineData(false)]
    public async Task AcceptOrRejectAsync_ExpiredOfferStillFails(bool accept)
    {
        await using var context = CreateContext();
        var now = new DateTimeOffset(2026, 9, 20, 12, 0, 0, TimeSpan.Zero);
        var tenantId = Guid.NewGuid();
        var offer = AddRentalOffer(context, tenantId, RentalOfferStatus.Pending, now);
        await context.SaveChangesAsync();
        var service = CreateService(context, now);

        var exception = await Assert.ThrowsAsync<RentalOfferServiceException>(() => accept
            ? service.AcceptAsync(offer.Id, tenantId)
            : service.RejectAsync(offer.Id, tenantId));

        Assert.Equal(RentalOfferServiceError.Conflict, exception.Error);
        Assert.Equal(RentalOfferStatus.Expired, offer.Status);
    }

    private static RentalOfferService CreateService(
        ApplicationDbContext context,
        DateTimeOffset? now = null)
        => new(context, new TestTimeProvider(now ?? DateTimeOffset.UtcNow));

    private static CreateRentalOfferDto CreateOfferRequest(
        Guid applicationId,
        DateTimeOffset now) => new()
    {
        RentalApplicationId = applicationId,
        MonthlyRent = 85000m,
        SecurityDeposit = 170000m,
        ProposedStartDate = DateOnly.FromDateTime(now.UtcDateTime.AddDays(30)),
        ProposedEndDate = DateOnly.FromDateTime(now.UtcDateTime.AddMonths(12)),
        ExpiresAt = now.AddDays(7)
    };

    private sealed class TestTimeProvider(DateTimeOffset utcNow) : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() => utcNow;
    }

    private static ApplicationDbContext CreateContext()
    {
        var options = new DbContextOptionsBuilder<ApplicationDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString())
            .Options;

        return new ApplicationDbContext(options);
    }

    private static RentalApplication AddRentalApplication(
        ApplicationDbContext context,
        RentalApplicationStatus status)
    {
        var propertyId = Guid.NewGuid();
        context.Properties.Add(new Property
        {
            Id = propertyId,
            LandlordId = Guid.NewGuid(),
            Title = "Test Property",
            Description = "Test description",
            Address = "123 Test Street",
            City = "Colombo",
            MonthlyRent = 75000m,
            Bedrooms = 2,
            Bathrooms = 1
        });

        var application = new RentalApplication
        {
            Id = Guid.NewGuid(),
            TenantId = Guid.NewGuid(),
            PropertyId = propertyId,
            MoveInDate = DateOnly.FromDateTime(DateTime.UtcNow.AddDays(30)),
            MonthlyIncome = 250000m,
            Occupation = "Software Engineer",
            NumberOfOccupants = 2,
            Status = status,
            CreatedAt = DateTimeOffset.UtcNow
        };

        context.RentalApplications.Add(application);

        return application;
    }

    private static RentalOffer AddRentalOffer(
        ApplicationDbContext context,
        Guid tenantId,
        RentalOfferStatus status,
        DateTimeOffset expiresAt)
    {
        var offer = new RentalOffer
        {
            Id = Guid.NewGuid(),
            RentalApplicationId = Guid.NewGuid(),
            TenantId = tenantId,
            PropertyId = Guid.NewGuid(),
            MonthlyRent = 85000m,
            SecurityDeposit = 170000m,
            ProposedStartDate = DateOnly.FromDateTime(DateTime.UtcNow.AddDays(30)),
            ProposedEndDate = DateOnly.FromDateTime(DateTime.UtcNow.AddMonths(12)),
            ExpiresAt = expiresAt,
            Status = status,
            CreatedAt = DateTimeOffset.UtcNow
        };

        context.RentalOffers.Add(offer);

        return offer;
    }
}
