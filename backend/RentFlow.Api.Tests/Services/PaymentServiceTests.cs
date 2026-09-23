using Microsoft.EntityFrameworkCore;
using RentFlow.Api.Data;
using RentFlow.Api.DTOs.Payments;
using RentFlow.Api.Models;
using RentFlow.Api.Services;
using Xunit;

namespace RentFlow.Api.Tests.Services;

public class PaymentServiceTests
{
    [Fact]
    public async Task CreateAsync_WithValidRentScheduleItem_CreatesPendingPayment()
    {
        await using var dbContext = CreateDbContext();

        var tenantId = Guid.NewGuid();

        var leaseAgreement = new LeaseAgreement
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

        dbContext.LeaseAgreements.Add(leaseAgreement);

        await dbContext.SaveChangesAsync();

        var rentScheduleItem = new RentScheduleItem
        {
            LeaseAgreementId = leaseAgreement.Id,
            DueDate = new DateOnly(2026, 10, 1),
            Amount = 85000m,
            Status = RentScheduleStatus.Pending
        };

        dbContext.RentScheduleItems.Add(rentScheduleItem);

        await dbContext.SaveChangesAsync();

        var service = new PaymentService(dbContext);

        var dto = new CreatePaymentDto
        {
            RentScheduleItemId = rentScheduleItem.Id,
            PaymentMethod = "BankTransfer",
            TransactionReference = "TXN-001"
        };

        var result = await service.CreateAsync(
            dto,
            tenantId);

        Assert.Equal(rentScheduleItem.Id, result.RentScheduleItemId);
        Assert.Equal(tenantId, result.TenantId);
        Assert.Equal(85000m, result.Amount);
        Assert.Equal("BankTransfer", result.PaymentMethod);
        Assert.Equal("TXN-001", result.TransactionReference);
        Assert.Equal(PaymentStatus.Pending, result.Status);
        Assert.Null(result.PaidAt);

        var savedPayment = await dbContext.Payments.SingleAsync();

        Assert.Equal(85000m, savedPayment.Amount);
        Assert.Equal(PaymentStatus.Pending, savedPayment.Status);
    }

    [Fact]
    public async Task CreateAsync_WhenRentScheduleItemBelongsToAnotherTenant_ThrowsConflict()
    {
        await using var dbContext = CreateDbContext();

        var tenantId = Guid.NewGuid();
        var otherTenantId = Guid.NewGuid();

        var leaseAgreement = new LeaseAgreement
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

        dbContext.LeaseAgreements.Add(leaseAgreement);

        await dbContext.SaveChangesAsync();

        var rentScheduleItem = new RentScheduleItem
        {
            LeaseAgreementId = leaseAgreement.Id,
            DueDate = new DateOnly(2026, 10, 1),
            Amount = 85000m,
            Status = RentScheduleStatus.Pending
        };

        dbContext.RentScheduleItems.Add(rentScheduleItem);

        await dbContext.SaveChangesAsync();

        var service = new PaymentService(dbContext);

        var dto = new CreatePaymentDto
        {
            RentScheduleItemId = rentScheduleItem.Id,
            PaymentMethod = "BankTransfer",
            TransactionReference = "TXN-002"
        };

        var exception = await Assert.ThrowsAsync<PaymentServiceException>(
            () => service.CreateAsync(
                dto,
                otherTenantId));

        Assert.Equal(
            PaymentServiceError.Conflict,
            exception.Error);

        Assert.Empty(dbContext.Payments);
    }

    [Fact]
    public async Task CreateAsync_WhenRentScheduleItemAlreadyPaid_ThrowsConflict()
    {
        await using var dbContext = CreateDbContext();

        var tenantId = Guid.NewGuid();

        var leaseAgreement = new LeaseAgreement
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

        dbContext.LeaseAgreements.Add(leaseAgreement);

        await dbContext.SaveChangesAsync();

        var rentScheduleItem = new RentScheduleItem
        {
            LeaseAgreementId = leaseAgreement.Id,
            DueDate = new DateOnly(2026, 10, 1),
            Amount = 85000m,
            Status = RentScheduleStatus.Paid
        };

        dbContext.RentScheduleItems.Add(rentScheduleItem);

        await dbContext.SaveChangesAsync();

        var service = new PaymentService(dbContext);

        var dto = new CreatePaymentDto
        {
            RentScheduleItemId = rentScheduleItem.Id,
            PaymentMethod = "BankTransfer",
            TransactionReference = "TXN-003"
        };

        var exception = await Assert.ThrowsAsync<PaymentServiceException>(
            () => service.CreateAsync(
                dto,
                tenantId));

        Assert.Equal(
            PaymentServiceError.Conflict,
            exception.Error);

        Assert.Empty(dbContext.Payments);
    }

    [Fact]
    public async Task CompleteAsync_WithPendingPayment_CompletesPaymentAndMarksRentPaid()
    {
        await using var dbContext = CreateDbContext();

        var tenantId = Guid.NewGuid();

        var leaseAgreement = new LeaseAgreement
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

        dbContext.LeaseAgreements.Add(leaseAgreement);

        await dbContext.SaveChangesAsync();

        var rentScheduleItem = new RentScheduleItem
        {
            LeaseAgreementId = leaseAgreement.Id,
            DueDate = new DateOnly(2026, 10, 1),
            Amount = 85000m,
            Status = RentScheduleStatus.Pending
        };

        dbContext.RentScheduleItems.Add(rentScheduleItem);

        await dbContext.SaveChangesAsync();

        var payment = new Payment
        {
            RentScheduleItemId = rentScheduleItem.Id,
            TenantId = tenantId,
            Amount = 85000m,
            PaymentMethod = "BankTransfer",
            TransactionReference = "TXN-004",
            Status = PaymentStatus.Pending
        };

        dbContext.Payments.Add(payment);

        await dbContext.SaveChangesAsync();

        var service = new PaymentService(dbContext);

        var result = await service.CompleteAsync(payment.Id);

        Assert.Equal(PaymentStatus.Completed, result.Status);
        Assert.NotNull(result.PaidAt);

        var savedPayment = await dbContext.Payments.SingleAsync();

        Assert.Equal(PaymentStatus.Completed, savedPayment.Status);
        Assert.NotNull(savedPayment.PaidAt);

        var savedRentScheduleItem = await dbContext.RentScheduleItems.SingleAsync();

        Assert.Equal(
            RentScheduleStatus.Paid,
            savedRentScheduleItem.Status);

        Assert.NotNull(savedRentScheduleItem.UpdatedAt);
    }

    [Fact]
    public async Task CompleteAsync_WhenAnotherPaymentSettledSchedule_LeavesSecondPaymentUnchanged()
    {
        await using var dbContext = CreateDbContext();
        var tenantId = Guid.NewGuid();
        var schedule = await CreateRentScheduleItemAsync(dbContext, tenantId);
        var firstPayment = CreatePayment(schedule, tenantId);
        var secondPayment = CreatePayment(schedule, tenantId);
        dbContext.Payments.AddRange(firstPayment, secondPayment);
        await dbContext.SaveChangesAsync();

        var service = new PaymentService(dbContext);
        await service.CompleteAsync(firstPayment.Id);

        var exception = await Assert.ThrowsAsync<PaymentServiceException>(
            () => service.CompleteAsync(secondPayment.Id));

        Assert.Equal(PaymentServiceError.Conflict, exception.Error);
        Assert.Equal(PaymentStatus.Pending, secondPayment.Status);
        Assert.Equal(RentScheduleStatus.Paid, schedule.Status);

        var savedSecondPayment = await dbContext.Payments
            .AsNoTracking()
            .SingleAsync(payment => payment.Id == secondPayment.Id);
        var savedSchedule = await dbContext.RentScheduleItems
            .AsNoTracking()
            .SingleAsync(item => item.Id == schedule.Id);
        Assert.Equal(PaymentStatus.Pending, savedSecondPayment.Status);
        Assert.Equal(RentScheduleStatus.Paid, savedSchedule.Status);
    }

    [Fact]
    public async Task CompleteAsync_WhenCompletedPaymentExists_RejectsEvenIfScheduleIsNotMarkedPaid()
    {
        await using var dbContext = CreateDbContext();
        var tenantId = Guid.NewGuid();
        var schedule = await CreateRentScheduleItemAsync(dbContext, tenantId);
        var completedPayment = CreatePayment(schedule, tenantId);
        completedPayment.Status = PaymentStatus.Completed;
        var pendingPayment = CreatePayment(schedule, tenantId);
        dbContext.Payments.AddRange(completedPayment, pendingPayment);
        await dbContext.SaveChangesAsync();

        var exception = await Assert.ThrowsAsync<PaymentServiceException>(
            () => new PaymentService(dbContext).CompleteAsync(pendingPayment.Id));

        Assert.Equal(PaymentServiceError.Conflict, exception.Error);
        Assert.Equal(PaymentStatus.Pending, pendingPayment.Status);
        Assert.Equal(RentScheduleStatus.Pending, schedule.Status);
    }

    [Fact]
    public async Task CompleteAsync_WhenPaymentIsAlreadyCompleted_LeavesPaidScheduleValid()
    {
        await using var dbContext = CreateDbContext();
        var tenantId = Guid.NewGuid();
        var schedule = await CreateRentScheduleItemAsync(dbContext, tenantId);
        var payment = CreatePayment(schedule, tenantId);
        dbContext.Payments.Add(payment);
        await dbContext.SaveChangesAsync();

        var service = new PaymentService(dbContext);
        await service.CompleteAsync(payment.Id);

        var exception = await Assert.ThrowsAsync<PaymentServiceException>(
            () => service.CompleteAsync(payment.Id));

        Assert.Equal(PaymentServiceError.Conflict, exception.Error);
        Assert.Equal(PaymentStatus.Completed, payment.Status);
        Assert.Equal(RentScheduleStatus.Paid, schedule.Status);
    }

    [Fact]
    public async Task CompleteAsync_AfterFailedAttempt_AllowsLaterPendingAttempt()
    {
        await using var dbContext = CreateDbContext();
        var tenantId = Guid.NewGuid();
        var schedule = await CreateRentScheduleItemAsync(dbContext, tenantId);
        var failedAttempt = CreatePayment(schedule, tenantId);
        dbContext.Payments.Add(failedAttempt);
        await dbContext.SaveChangesAsync();

        var service = new PaymentService(dbContext);
        await service.FailAsync(failedAttempt.Id);
        Assert.Equal(RentScheduleStatus.Pending, schedule.Status);

        var retryAttempt = await service.CreateAsync(
            new CreatePaymentDto
            {
                RentScheduleItemId = schedule.Id,
                PaymentMethod = "BankTransfer"
            },
            tenantId);
        Assert.Equal(PaymentStatus.Pending, retryAttempt.Status);

        var result = await service.CompleteAsync(retryAttempt.Id);

        Assert.Equal(PaymentStatus.Completed, result.Status);
        Assert.Equal(PaymentStatus.Failed, failedAttempt.Status);
        Assert.Equal(RentScheduleStatus.Paid, schedule.Status);
    }

    [Fact]
    public async Task CompleteAsync_WithOverdueSchedule_PaysTheScheduleItem()
    {
        await using var dbContext = CreateDbContext();
        var tenantId = Guid.NewGuid();
        var schedule = await CreateRentScheduleItemAsync(dbContext, tenantId);
        schedule.Status = RentScheduleStatus.Overdue;
        var payment = CreatePayment(schedule, tenantId);
        dbContext.Payments.Add(payment);
        await dbContext.SaveChangesAsync();

        var result = await new PaymentService(dbContext).CompleteAsync(payment.Id);

        Assert.Equal(PaymentStatus.Completed, result.Status);
        Assert.Equal(RentScheduleStatus.Paid, schedule.Status);
    }

    [Fact]
    public async Task FailAsync_WithPendingPayment_MarksPaymentAsFailed()
    {
        await using var dbContext = CreateDbContext();

        var tenantId = Guid.NewGuid();

        var leaseAgreement = new LeaseAgreement
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

        dbContext.LeaseAgreements.Add(leaseAgreement);

        await dbContext.SaveChangesAsync();

        var rentScheduleItem = new RentScheduleItem
        {
            LeaseAgreementId = leaseAgreement.Id,
            DueDate = new DateOnly(2026, 10, 1),
            Amount = 85000m,
            Status = RentScheduleStatus.Pending
        };

        dbContext.RentScheduleItems.Add(rentScheduleItem);

        await dbContext.SaveChangesAsync();

        var payment = new Payment
        {
            RentScheduleItemId = rentScheduleItem.Id,
            TenantId = tenantId,
            Amount = 85000m,
            PaymentMethod = "BankTransfer",
            TransactionReference = "TXN-005",
            Status = PaymentStatus.Pending
        };

        dbContext.Payments.Add(payment);

        await dbContext.SaveChangesAsync();

        var service = new PaymentService(dbContext);

        var result = await service.FailAsync(payment.Id);

        Assert.Equal(
            PaymentStatus.Failed,
            result.Status);

        var savedPayment = await dbContext.Payments.SingleAsync();

        Assert.Equal(
            PaymentStatus.Failed,
            savedPayment.Status);

        Assert.NotNull(savedPayment.UpdatedAt);

        var savedRentScheduleItem = await dbContext.RentScheduleItems.SingleAsync();

        Assert.Equal(
            RentScheduleStatus.Pending,
            savedRentScheduleItem.Status);
    }

    private static ApplicationDbContext CreateDbContext()
    {
        var options = new DbContextOptionsBuilder<ApplicationDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString())
            .Options;

        return new ApplicationDbContext(options);
    }

    private static async Task<RentScheduleItem> CreateRentScheduleItemAsync(
        ApplicationDbContext dbContext,
        Guid tenantId)
    {
        var leaseAgreement = new LeaseAgreement
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
        dbContext.LeaseAgreements.Add(leaseAgreement);
        await dbContext.SaveChangesAsync();

        var schedule = new RentScheduleItem
        {
            LeaseAgreementId = leaseAgreement.Id,
            DueDate = new DateOnly(2026, 10, 1),
            Amount = 85000m,
            Status = RentScheduleStatus.Pending
        };
        dbContext.RentScheduleItems.Add(schedule);
        await dbContext.SaveChangesAsync();
        return schedule;
    }

    private static Payment CreatePayment(
        RentScheduleItem schedule,
        Guid tenantId) => new()
    {
        RentScheduleItemId = schedule.Id,
        TenantId = tenantId,
        Amount = schedule.Amount,
        PaymentMethod = "BankTransfer",
        Status = PaymentStatus.Pending
    };
}
