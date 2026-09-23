using Microsoft.EntityFrameworkCore;
using RentFlow.Api.Data;
using RentFlow.Api.DTOs.LeaseAgreements;
using RentFlow.Api.Models;
using RentFlow.Api.Services;
using Xunit;

namespace RentFlow.Api.Tests.Services;

public class LeaseAgreementServiceTests
{
    [Fact]
    public async Task CreateAsync_WithAcceptedRentalOffer_CreatesPendingLease()
    {
        await using var dbContext = CreateDbContext();

        var rentalApplication = new RentalApplication
        {
            TenantId = Guid.NewGuid(),
            PropertyId = Guid.NewGuid(),
            MoveInDate = DateOnly.FromDateTime(DateTime.UtcNow.AddDays(10)),
            Status = RentalApplicationStatus.Approved
        };

        dbContext.Properties.Add(CreateProperty(rentalApplication.PropertyId));

        dbContext.RentalApplications.Add(rentalApplication);

        var rentalOffer = new RentalOffer
        {
            RentalApplicationId = rentalApplication.Id,
            TenantId = rentalApplication.TenantId,
            PropertyId = rentalApplication.PropertyId,
            MonthlyRent = 85000m,
            SecurityDeposit = 170000m,
            ProposedStartDate = DateOnly.FromDateTime(DateTime.UtcNow.AddDays(10)),
            ProposedEndDate = DateOnly.FromDateTime(DateTime.UtcNow.AddYears(1)),
            ExpiresAt = DateTimeOffset.UtcNow.AddDays(5),
            Status = RentalOfferStatus.Accepted
        };

        dbContext.RentalOffers.Add(rentalOffer);

        await dbContext.SaveChangesAsync();

        var service = new LeaseAgreementService(dbContext);

        var dto = new CreateLeaseAgreementDto
        {
            RentalOfferId = rentalOffer.Id
        };

        var result = await service.CreateAsync(dto);

        Assert.Equal(rentalOffer.Id, result.RentalOfferId);
        Assert.Equal(rentalOffer.TenantId, result.TenantId);
        Assert.Equal(rentalOffer.PropertyId, result.PropertyId);
        Assert.Equal(rentalOffer.MonthlyRent, result.MonthlyRent);
        Assert.Equal(rentalOffer.SecurityDeposit, result.SecurityDeposit);
        Assert.Equal(rentalOffer.ProposedStartDate, result.StartDate);
        Assert.Equal(rentalOffer.ProposedEndDate, result.EndDate);
        Assert.Equal(LeaseAgreementStatus.Pending, result.Status);

        var savedLease = await dbContext.LeaseAgreements.SingleAsync();

        Assert.Equal(rentalOffer.Id, savedLease.RentalOfferId);
    }

    [Fact]
    public async Task CreateAsync_WithNonAcceptedRentalOffer_ThrowsConflict()
    {
        await using var dbContext = CreateDbContext();

        var rentalApplication = new RentalApplication
        {
            TenantId = Guid.NewGuid(),
            PropertyId = Guid.NewGuid(),
            MoveInDate = DateOnly.FromDateTime(DateTime.UtcNow.AddDays(10)),
            Status = RentalApplicationStatus.Approved
        };

        dbContext.RentalApplications.Add(rentalApplication);

        var rentalOffer = new RentalOffer
        {
            RentalApplicationId = rentalApplication.Id,
            TenantId = rentalApplication.TenantId,
            PropertyId = rentalApplication.PropertyId,
            MonthlyRent = 85000m,
            SecurityDeposit = 170000m,
            ProposedStartDate = DateOnly.FromDateTime(DateTime.UtcNow.AddDays(10)),
            ProposedEndDate = DateOnly.FromDateTime(DateTime.UtcNow.AddYears(1)),
            ExpiresAt = DateTimeOffset.UtcNow.AddDays(5),
            Status = RentalOfferStatus.Pending
        };

        dbContext.RentalOffers.Add(rentalOffer);

        await dbContext.SaveChangesAsync();

        var service = new LeaseAgreementService(dbContext);

        var dto = new CreateLeaseAgreementDto
        {
            RentalOfferId = rentalOffer.Id
        };

        var exception = await Assert.ThrowsAsync<LeaseAgreementServiceException>(
            () => service.CreateAsync(dto));

        Assert.Equal(
            LeaseAgreementServiceError.Conflict,
            exception.Error);

        Assert.Empty(dbContext.LeaseAgreements);
    }

    [Fact]
    public async Task CreateAsync_WhenLeaseAlreadyExists_ThrowsConflict()
    {
        await using var dbContext = CreateDbContext();

        var rentalApplication = new RentalApplication
        {
            TenantId = Guid.NewGuid(),
            PropertyId = Guid.NewGuid(),
            MoveInDate = DateOnly.FromDateTime(DateTime.UtcNow.AddDays(10)),
            Status = RentalApplicationStatus.Approved
        };

        dbContext.RentalApplications.Add(rentalApplication);

        var rentalOffer = new RentalOffer
        {
            RentalApplicationId = rentalApplication.Id,
            TenantId = rentalApplication.TenantId,
            PropertyId = rentalApplication.PropertyId,
            MonthlyRent = 85000m,
            SecurityDeposit = 170000m,
            ProposedStartDate = DateOnly.FromDateTime(DateTime.UtcNow.AddDays(10)),
            ProposedEndDate = DateOnly.FromDateTime(DateTime.UtcNow.AddYears(1)),
            ExpiresAt = DateTimeOffset.UtcNow.AddDays(5),
            Status = RentalOfferStatus.Accepted
        };

        dbContext.RentalOffers.Add(rentalOffer);

        await dbContext.SaveChangesAsync();

        var existingLease = new LeaseAgreement
        {
            RentalOfferId = rentalOffer.Id,
            TenantId = rentalOffer.TenantId,
            PropertyId = rentalOffer.PropertyId,
            MonthlyRent = rentalOffer.MonthlyRent,
            SecurityDeposit = rentalOffer.SecurityDeposit,
            StartDate = rentalOffer.ProposedStartDate,
            EndDate = rentalOffer.ProposedEndDate,
            Status = LeaseAgreementStatus.Pending
        };

        dbContext.LeaseAgreements.Add(existingLease);

        await dbContext.SaveChangesAsync();

        var service = new LeaseAgreementService(dbContext);

        var dto = new CreateLeaseAgreementDto
        {
            RentalOfferId = rentalOffer.Id
        };

        var exception = await Assert.ThrowsAsync<LeaseAgreementServiceException>(
            () => service.CreateAsync(dto));

        Assert.Equal(
            LeaseAgreementServiceError.Conflict,
            exception.Error);

        Assert.Single(dbContext.LeaseAgreements);
    }

    [Fact]
    public async Task CreateAsync_WithAcceptedOfferAndMissingProperty_ThrowsNotFound()
    {
        await using var dbContext = CreateDbContext();
        var rentalOffer = new RentalOffer
        {
            RentalApplicationId = Guid.NewGuid(),
            TenantId = Guid.NewGuid(),
            PropertyId = Guid.NewGuid(),
            MonthlyRent = 85000m,
            SecurityDeposit = 170000m,
            ProposedStartDate = DateOnly.FromDateTime(DateTime.UtcNow.AddDays(10)),
            ProposedEndDate = DateOnly.FromDateTime(DateTime.UtcNow.AddYears(1)),
            ExpiresAt = DateTimeOffset.UtcNow.AddDays(5),
            Status = RentalOfferStatus.Accepted
        };
        dbContext.RentalOffers.Add(rentalOffer);
        await dbContext.SaveChangesAsync();

        var service = new LeaseAgreementService(dbContext);
        var exception = await Assert.ThrowsAsync<LeaseAgreementServiceException>(
            () => service.CreateAsync(new CreateLeaseAgreementDto
            {
                RentalOfferId = rentalOffer.Id
            }));

        Assert.Equal(LeaseAgreementServiceError.NotFound, exception.Error);
        Assert.Empty(dbContext.LeaseAgreements);
    }

    [Fact]
    public async Task ActivateAsync_WithPendingLease_ChangesStatusToActive()
    {
        await using var dbContext = CreateDbContext();

        var leaseAgreement = new LeaseAgreement
        {
            RentalOfferId = Guid.NewGuid(),
            TenantId = Guid.NewGuid(),
            PropertyId = Guid.NewGuid(),
            MonthlyRent = 85000m,
            SecurityDeposit = 170000m,
            StartDate = DateOnly.FromDateTime(DateTime.UtcNow.AddDays(10)),
            EndDate = DateOnly.FromDateTime(DateTime.UtcNow.AddYears(1)),
            Status = LeaseAgreementStatus.Pending
        };

        dbContext.LeaseAgreements.Add(leaseAgreement);

        await dbContext.SaveChangesAsync();

        var service = new LeaseAgreementService(dbContext);

        var result = await service.ActivateAsync(leaseAgreement.Id);

        Assert.Equal(
            LeaseAgreementStatus.Active,
            result.Status);

        var savedLease = await dbContext.LeaseAgreements.SingleAsync();

        Assert.Equal(
            LeaseAgreementStatus.Active,
            savedLease.Status);

        Assert.NotNull(savedLease.UpdatedAt);
    }

    [Fact]
    public async Task TerminateAsync_WithActiveLease_ChangesStatusToTerminated()
    {
        await using var dbContext = CreateDbContext();

        var leaseAgreement = new LeaseAgreement
        {
            RentalOfferId = Guid.NewGuid(),
            TenantId = Guid.NewGuid(),
            PropertyId = Guid.NewGuid(),
            MonthlyRent = 85000m,
            SecurityDeposit = 170000m,
            StartDate = DateOnly.FromDateTime(DateTime.UtcNow.AddDays(-30)),
            EndDate = DateOnly.FromDateTime(DateTime.UtcNow.AddMonths(11)),
            Status = LeaseAgreementStatus.Active
        };

        dbContext.LeaseAgreements.Add(leaseAgreement);

        await dbContext.SaveChangesAsync();

        var service = new LeaseAgreementService(dbContext);

        var result = await service.TerminateAsync(leaseAgreement.Id);

        Assert.Equal(
            LeaseAgreementStatus.Terminated,
            result.Status);

        var savedLease = await dbContext.LeaseAgreements.SingleAsync();

        Assert.Equal(
            LeaseAgreementStatus.Terminated,
            savedLease.Status);

        Assert.NotNull(savedLease.UpdatedAt);
    }

    [Fact]
    public async Task CompleteAsync_WithActiveLease_ChangesStatusToCompleted()
    {
        await using var dbContext = CreateDbContext();

        var leaseAgreement = new LeaseAgreement
        {
            RentalOfferId = Guid.NewGuid(),
            TenantId = Guid.NewGuid(),
            PropertyId = Guid.NewGuid(),
            MonthlyRent = 85000m,
            SecurityDeposit = 170000m,
            StartDate = DateOnly.FromDateTime(DateTime.UtcNow.AddYears(-1)),
            EndDate = DateOnly.FromDateTime(DateTime.UtcNow),
            Status = LeaseAgreementStatus.Active
        };

        dbContext.LeaseAgreements.Add(leaseAgreement);

        await dbContext.SaveChangesAsync();

        var service = new LeaseAgreementService(dbContext);

        var result = await service.CompleteAsync(leaseAgreement.Id);

        Assert.Equal(
            LeaseAgreementStatus.Completed,
            result.Status);

        var savedLease = await dbContext.LeaseAgreements.SingleAsync();

        Assert.Equal(
            LeaseAgreementStatus.Completed,
            savedLease.Status);

        Assert.NotNull(savedLease.UpdatedAt);
    }

    private static ApplicationDbContext CreateDbContext()
    {
        var options = new DbContextOptionsBuilder<ApplicationDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString())
            .Options;

        return new ApplicationDbContext(options);
    }

    private static Property CreateProperty(Guid id) => new()
    {
        Id = id,
        LandlordId = Guid.NewGuid(),
        Title = "Test Property",
        Description = "Test description",
        Address = "123 Test Street",
        City = "Colombo",
        MonthlyRent = 75000m,
        Bedrooms = 2,
        Bathrooms = 1
    };
}
