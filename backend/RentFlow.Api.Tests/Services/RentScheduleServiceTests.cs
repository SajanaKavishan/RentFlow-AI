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

        var service = CreateService(dbContext);

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

        var service = CreateService(dbContext);

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

        var service = CreateService(dbContext);

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

        var service = CreateService(dbContext);

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

        var service = CreateService(dbContext);

        var result = await service.GetByIdAsync(scheduleItem.Id);

        Assert.NotNull(result);
        Assert.Equal(scheduleItem.Id, result!.Id);
        Assert.Equal(leaseAgreement.Id, result.LeaseAgreementId);
        Assert.Equal(85000m, result.Amount);
        Assert.Equal(RentScheduleStatus.Pending, result.Status);
    }

    [Fact]
    public async Task GetByIdAsync_WhenPendingItemWasDueYesterday_MarksItOverdue()
    {
        await using var dbContext = CreateDbContext();
        var item = await CreateScheduleItemAsync(
            dbContext,
            Guid.NewGuid(),
            TestToday.AddDays(-1),
            RentScheduleStatus.Pending);
        var timeProvider = new TestTimeProvider(TestUtcNow);
        var service = new RentScheduleService(
            dbContext,
            new PropertyAccessGuard(dbContext),
            timeProvider);

        var result = await service.GetByIdAsync(item.Id);

        Assert.NotNull(result);
        Assert.Equal(RentScheduleStatus.Overdue, result!.Status);
        Assert.Equal(TestUtcNow, item.UpdatedAt);
    }

    [Fact]
    public async Task GetByTenantAsync_DueTodayAndFutureItemsRemainPending()
    {
        await using var dbContext = CreateDbContext();
        var tenantId = Guid.NewGuid();
        var dueToday = await CreateScheduleItemAsync(
            dbContext, tenantId, TestToday, RentScheduleStatus.Pending);
        var dueTomorrow = await CreateScheduleItemAsync(
            dbContext, tenantId, TestToday.AddDays(1), RentScheduleStatus.Pending);
        var service = new RentScheduleService(
            dbContext,
            new PropertyAccessGuard(dbContext),
            new TestTimeProvider(TestUtcNow));

        var result = await service.GetByTenantAsync(tenantId);

        Assert.All(result, item =>
            Assert.Equal(RentScheduleStatus.Pending, item.Status));
        Assert.Equal(RentScheduleStatus.Pending, dueToday.Status);
        Assert.Equal(RentScheduleStatus.Pending, dueTomorrow.Status);
        Assert.Null(dueToday.UpdatedAt);
        Assert.Null(dueTomorrow.UpdatedAt);
    }

    [Fact]
    public async Task GetByTenantAsync_PaidAndAlreadyOverduePastItemsKeepTheirStatuses()
    {
        await using var dbContext = CreateDbContext();
        var tenantId = Guid.NewGuid();
        var paid = await CreateScheduleItemAsync(
            dbContext, tenantId, TestToday.AddDays(-2), RentScheduleStatus.Paid);
        var overdue = await CreateScheduleItemAsync(
            dbContext, tenantId, TestToday.AddDays(-1), RentScheduleStatus.Overdue);
        var paidUpdatedAt = paid.UpdatedAt;
        var overdueUpdatedAt = overdue.UpdatedAt;
        var service = new RentScheduleService(
            dbContext,
            new PropertyAccessGuard(dbContext),
            new TestTimeProvider(TestUtcNow));

        var result = await service.GetByTenantAsync(tenantId);

        Assert.Contains(
            result,
            item => item.Id == paid.Id && item.Status == RentScheduleStatus.Paid);
        Assert.Contains(
            result,
            item => item.Id == overdue.Id && item.Status == RentScheduleStatus.Overdue);
        Assert.Equal(paidUpdatedAt, paid.UpdatedAt);
        Assert.Equal(overdueUpdatedAt, overdue.UpdatedAt);
    }

    [Fact]
    public async Task GetByIdAsync_ReprocessingOverdueItemDoesNotChangeItAgain()
    {
        await using var dbContext = CreateDbContext();
        var item = await CreateScheduleItemAsync(
            dbContext,
            Guid.NewGuid(),
            TestToday.AddDays(-1),
            RentScheduleStatus.Pending);
        var timeProvider = new TestTimeProvider(TestUtcNow);
        var service = new RentScheduleService(
            dbContext,
            new PropertyAccessGuard(dbContext),
            timeProvider);

        await service.GetByIdAsync(item.Id);
        var firstUpdatedAt = item.UpdatedAt;
        timeProvider.SetUtcNow(TestUtcNow.AddDays(1));
        await service.GetByIdAsync(item.Id);

        Assert.Equal(RentScheduleStatus.Overdue, item.Status);
        Assert.Equal(firstUpdatedAt, item.UpdatedAt);
    }

    [Fact]
    public async Task GetByTenantAsync_RefreshesOnlyThatTenantsSchedules()
    {
        await using var dbContext = CreateDbContext();
        var tenantId = Guid.NewGuid();
        var otherTenantId = Guid.NewGuid();
        var tenantItem = await CreateScheduleItemAsync(
            dbContext, tenantId, TestToday.AddDays(-1), RentScheduleStatus.Pending);
        var otherTenantItem = await CreateScheduleItemAsync(
            dbContext, otherTenantId, TestToday.AddDays(-1), RentScheduleStatus.Pending);
        var service = new RentScheduleService(
            dbContext,
            new PropertyAccessGuard(dbContext),
            new TestTimeProvider(TestUtcNow));

        var result = await service.GetByTenantAsync(tenantId);

        Assert.Single(result);
        Assert.Equal(tenantItem.Id, result[0].Id);
        Assert.Equal(RentScheduleStatus.Overdue, tenantItem.Status);
        Assert.Equal(RentScheduleStatus.Pending, otherTenantItem.Status);
        Assert.Null(otherTenantItem.UpdatedAt);
    }

    [Fact]
    public async Task GetOutstandingByTenantAsync_MixedScheduleIncludesOnlyPendingAndOverdueAmounts()
    {
        await using var dbContext = CreateDbContext();
        var tenantId = Guid.NewGuid();
        var pending = await CreateScheduleItemAsync(
            dbContext, tenantId, TestToday.AddDays(1), RentScheduleStatus.Pending, 100.25m);
        var overdue = await CreateScheduleItemAsync(
            dbContext, tenantId, TestToday.AddDays(-1), RentScheduleStatus.Overdue, 200.50m);
        var paid = await CreateScheduleItemAsync(
            dbContext, tenantId, TestToday.AddDays(-2), RentScheduleStatus.Paid, 300.75m);
        var summary = await CreateService(dbContext).GetOutstandingByTenantAsync(tenantId);

        Assert.Equal(100.25m, summary.TotalPending);
        Assert.Equal(200.50m, summary.TotalOverdue);
        Assert.Equal(300.75m, summary.TotalOutstanding);
        Assert.Equal(2, summary.Items.Count);
        Assert.Contains(summary.Items, item => item.Id == pending.Id);
        Assert.Contains(summary.Items, item => item.Id == overdue.Id);
        Assert.DoesNotContain(summary.Items, item => item.Id == paid.Id);
    }

    [Fact]
    public async Task GetOutstandingByTenantAsync_WithNoUnpaidItemsReturnsZeroTotalsAndNoItems()
    {
        await using var dbContext = CreateDbContext();
        var tenantId = Guid.NewGuid();
        await CreateScheduleItemAsync(
            dbContext, tenantId, TestToday.AddDays(-1), RentScheduleStatus.Paid, 300m);

        var summary = await CreateService(dbContext).GetOutstandingByTenantAsync(tenantId);

        Assert.Equal(0m, summary.TotalPending);
        Assert.Equal(0m, summary.TotalOverdue);
        Assert.Equal(0m, summary.TotalOutstanding);
        Assert.Empty(summary.Items);
    }

    [Fact]
    public async Task GetOutstandingByTenantAsync_PaymentAttemptsDoNotReduceScheduleBalance()
    {
        await using var dbContext = CreateDbContext();
        var tenantId = Guid.NewGuid();
        var item = await CreateScheduleItemAsync(
            dbContext, tenantId, TestToday.AddDays(1), RentScheduleStatus.Pending, 100m);
        dbContext.Payments.AddRange(
            new Payment
            {
                RentScheduleItemId = item.Id,
                TenantId = tenantId,
                Amount = 100m,
                PaymentMethod = "BankTransfer",
                Status = PaymentStatus.Pending
            },
            new Payment
            {
                RentScheduleItemId = item.Id,
                TenantId = tenantId,
                Amount = 100m,
                PaymentMethod = "BankTransfer",
                Status = PaymentStatus.Failed
            });
        await dbContext.SaveChangesAsync();

        var summary = await CreateService(dbContext).GetOutstandingByTenantAsync(tenantId);

        Assert.Equal(100m, summary.TotalPending);
        Assert.Equal(0m, summary.TotalOverdue);
        Assert.Equal(100m, summary.TotalOutstanding);
        Assert.Single(summary.Items);
    }

    [Fact]
    public async Task GetOutstandingByTenantAsync_RefreshesPastDuePendingBeforeCalculatingTotals()
    {
        await using var dbContext = CreateDbContext();
        var tenantId = Guid.NewGuid();
        var item = await CreateScheduleItemAsync(
            dbContext, tenantId, TestToday.AddDays(-1), RentScheduleStatus.Pending, 45.67m);

        var summary = await new RentScheduleService(
            dbContext,
            new PropertyAccessGuard(dbContext),
            new TestTimeProvider(TestUtcNow))
            .GetOutstandingByTenantAsync(tenantId);

        Assert.Equal(RentScheduleStatus.Overdue, item.Status);
        Assert.Equal(0m, summary.TotalPending);
        Assert.Equal(45.67m, summary.TotalOverdue);
        Assert.Equal(45.67m, summary.TotalOutstanding);
    }

    private static ApplicationDbContext CreateDbContext()
    {
        var options = new DbContextOptionsBuilder<ApplicationDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString())
            .Options;

        return new ApplicationDbContext(options);
    }

    private static RentScheduleService CreateService(ApplicationDbContext dbContext) =>
        new(
            dbContext,
            new PropertyAccessGuard(dbContext),
            new TestTimeProvider(new DateTimeOffset(2026, 9, 15, 12, 0, 0, TimeSpan.Zero)));

    private static async Task<RentScheduleItem> CreateScheduleItemAsync(
        ApplicationDbContext dbContext,
        Guid tenantId,
        DateOnly dueDate,
        RentScheduleStatus status,
        decimal amount = 85000m)
    {
        var lease = new LeaseAgreement
        {
            RentalOfferId = Guid.NewGuid(),
            TenantId = tenantId,
            PropertyId = Guid.NewGuid(),
            MonthlyRent = amount,
            SecurityDeposit = 170000m,
            StartDate = dueDate,
            EndDate = dueDate.AddMonths(12),
            Status = LeaseAgreementStatus.Active
        };
        dbContext.LeaseAgreements.Add(lease);
        await dbContext.SaveChangesAsync();

        var item = new RentScheduleItem
        {
            LeaseAgreementId = lease.Id,
            DueDate = dueDate,
            Amount = amount,
            Status = status
        };
        dbContext.RentScheduleItems.Add(item);
        await dbContext.SaveChangesAsync();
        return item;
    }

    private static readonly DateTimeOffset TestUtcNow =
        new(2026, 10, 15, 12, 0, 0, TimeSpan.Zero);

    private static readonly DateOnly TestToday = new(2026, 10, 15);

    private sealed class TestTimeProvider(DateTimeOffset utcNow) : TimeProvider
    {
        private DateTimeOffset _utcNow = utcNow;

        public override DateTimeOffset GetUtcNow() => _utcNow;

        public void SetUtcNow(DateTimeOffset utcNow) => _utcNow = utcNow;
    }
}
