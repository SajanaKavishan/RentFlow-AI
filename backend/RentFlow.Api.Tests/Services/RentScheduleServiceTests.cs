using Microsoft.EntityFrameworkCore;
using RentFlow.Api.Data;
using RentFlow.Api.Models;
using RentFlow.Api.Services;
using Xunit;

namespace RentFlow.Api.Tests.Services;

public class RentScheduleServiceTests
{
    [Fact]
    public async Task GenerateForLeaseAsync_WithActiveLease_CreatesMonthlyScheduleItems()
    {
        await using var dbContext = CreateDbContext();

        var leaseAgreement = new LeaseAgreement
        {
            RentalOfferId = Guid.NewGuid(),
            TenantId = Guid.NewGuid(),
            PropertyId = Guid.NewGuid(),
            MonthlyRent = 85000m,
            SecurityDeposit = 170000m,
            StartDate = new DateOnly(2026, 10, 1),
            EndDate = new DateOnly(2027, 9, 30),
            Status = LeaseAgreementStatus.Active
        };

        dbContext.LeaseAgreements.Add(leaseAgreement);

        await dbContext.SaveChangesAsync();

        var service = new RentScheduleService(dbContext);

        var result = await service.GenerateForLeaseAsync(
            leaseAgreement.Id);

        Assert.Equal(12, result.Count);

        Assert.All(result, item =>
        {
            Assert.Equal(leaseAgreement.Id, item.LeaseAgreementId);
            Assert.Equal(85000m, item.Amount);
            Assert.Equal(RentScheduleStatus.Pending, item.Status);
        });

        var savedItems = await dbContext.RentScheduleItems
            .OrderBy(item => item.DueDate)
            .ToListAsync();

        Assert.Equal(12, savedItems.Count);

        Assert.Equal(
            new DateOnly(2026, 10, 1),
            savedItems.First().DueDate);

        Assert.Equal(
            new DateOnly(2027, 9, 1),
            savedItems.Last().DueDate);
    }

    [Fact]
    public async Task GenerateForLeaseAsync_WithNonActiveLease_ThrowsConflict()
    {
        await using var dbContext = CreateDbContext();

        var leaseAgreement = new LeaseAgreement
        {
            RentalOfferId = Guid.NewGuid(),
            TenantId = Guid.NewGuid(),
            PropertyId = Guid.NewGuid(),
            MonthlyRent = 85000m,
            SecurityDeposit = 170000m,
            StartDate = new DateOnly(2026, 10, 1),
            EndDate = new DateOnly(2027, 9, 30),
            Status = LeaseAgreementStatus.Pending
        };

        dbContext.LeaseAgreements.Add(leaseAgreement);

        await dbContext.SaveChangesAsync();

        var service = new RentScheduleService(dbContext);

        var exception = await Assert.ThrowsAsync<RentScheduleServiceException>(
            () => service.GenerateForLeaseAsync(leaseAgreement.Id));

        Assert.Equal(
            RentScheduleServiceError.Conflict,
            exception.Error);

        Assert.Empty(dbContext.RentScheduleItems);
    }

    [Fact]
    public async Task GenerateForLeaseAsync_WhenScheduleAlreadyExists_ThrowsConflict()
    {
        await using var dbContext = CreateDbContext();

        var leaseAgreement = new LeaseAgreement
        {
            RentalOfferId = Guid.NewGuid(),
            TenantId = Guid.NewGuid(),
            PropertyId = Guid.NewGuid(),
            MonthlyRent = 85000m,
            SecurityDeposit = 170000m,
            StartDate = new DateOnly(2026, 10, 1),
            EndDate = new DateOnly(2027, 9, 30),
            Status = LeaseAgreementStatus.Active
        };

        dbContext.LeaseAgreements.Add(leaseAgreement);

        await dbContext.SaveChangesAsync();

        var existingScheduleItem = new RentScheduleItem
        {
            LeaseAgreementId = leaseAgreement.Id,
            DueDate = leaseAgreement.StartDate,
            Amount = leaseAgreement.MonthlyRent,
            Status = RentScheduleStatus.Pending
        };

        dbContext.RentScheduleItems.Add(existingScheduleItem);

        await dbContext.SaveChangesAsync();

        var service = new RentScheduleService(dbContext);

        var exception = await Assert.ThrowsAsync<RentScheduleServiceException>(
            () => service.GenerateForLeaseAsync(leaseAgreement.Id));

        Assert.Equal(
            RentScheduleServiceError.Conflict,
            exception.Error);

        Assert.Single(dbContext.RentScheduleItems);
    }

    [Fact]
    public async Task GetByTenantAsync_ReturnsOnlyTenantScheduleItems()
    {
        await using var dbContext = CreateDbContext();

        var tenantId = Guid.NewGuid();
        var otherTenantId = Guid.NewGuid();

        var tenantLease = new LeaseAgreement
        {
            RentalOfferId = Guid.NewGuid(),
            TenantId = tenantId,
            PropertyId = Guid.NewGuid(),
            MonthlyRent = 85000m,
            SecurityDeposit = 170000m,
            StartDate = new DateOnly(2026, 10, 1),
            EndDate = new DateOnly(2027, 9, 30),
            Status = LeaseAgreementStatus.Active
        };

        var otherLease = new LeaseAgreement
        {
            RentalOfferId = Guid.NewGuid(),
            TenantId = otherTenantId,
            PropertyId = Guid.NewGuid(),
            MonthlyRent = 95000m,
            SecurityDeposit = 190000m,
            StartDate = new DateOnly(2026, 10, 1),
            EndDate = new DateOnly(2027, 9, 30),
            Status = LeaseAgreementStatus.Active
        };

        dbContext.LeaseAgreements.AddRange(
            tenantLease,
            otherLease);

        await dbContext.SaveChangesAsync();

        dbContext.RentScheduleItems.AddRange(
            new RentScheduleItem
            {
                LeaseAgreementId = tenantLease.Id,
                DueDate = new DateOnly(2026, 10, 1),
                Amount = 85000m,
                Status = RentScheduleStatus.Pending
            },
            new RentScheduleItem
            {
                LeaseAgreementId = tenantLease.Id,
                DueDate = new DateOnly(2026, 11, 1),
                Amount = 85000m,
                Status = RentScheduleStatus.Pending
            },
            new RentScheduleItem
            {
                LeaseAgreementId = otherLease.Id,
                DueDate = new DateOnly(2026, 10, 1),
                Amount = 95000m,
                Status = RentScheduleStatus.Pending
            });

        await dbContext.SaveChangesAsync();

        var service = new RentScheduleService(dbContext);

        var result = await service.GetByTenantAsync(tenantId);

        Assert.Equal(2, result.Count);

        Assert.All(result, item =>
        {
            Assert.Equal(tenantLease.Id, item.LeaseAgreementId);
        });
    }

    [Fact]
    public async Task GetByIdAsync_WhenItemExists_ReturnsScheduleItem()
    {
        await using var dbContext = CreateDbContext();

        var leaseAgreement = new LeaseAgreement
        {
            RentalOfferId = Guid.NewGuid(),
            TenantId = Guid.NewGuid(),
            PropertyId = Guid.NewGuid(),
            MonthlyRent = 85000m,
            SecurityDeposit = 170000m,
            StartDate = new DateOnly(2026, 10, 1),
            EndDate = new DateOnly(2027, 9, 30),
            Status = LeaseAgreementStatus.Active
        };

        dbContext.LeaseAgreements.Add(leaseAgreement);

        await dbContext.SaveChangesAsync();

        var scheduleItem = new RentScheduleItem
        {
            LeaseAgreementId = leaseAgreement.Id,
            DueDate = new DateOnly(2026, 10, 1),
            Amount = 85000m,
            Status = RentScheduleStatus.Pending
        };

        dbContext.RentScheduleItems.Add(scheduleItem);

        await dbContext.SaveChangesAsync();

        var service = new RentScheduleService(dbContext);

        var result = await service.GetByIdAsync(scheduleItem.Id);

        Assert.NotNull(result);
        Assert.Equal(scheduleItem.Id, result!.Id);
        Assert.Equal(leaseAgreement.Id, result.LeaseAgreementId);
        Assert.Equal(85000m, result.Amount);
        Assert.Equal(RentScheduleStatus.Pending, result.Status);
    }
    private static ApplicationDbContext CreateDbContext()
    {
        var options = new DbContextOptionsBuilder<ApplicationDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString())
            .Options;

        return new ApplicationDbContext(options);
    }
}