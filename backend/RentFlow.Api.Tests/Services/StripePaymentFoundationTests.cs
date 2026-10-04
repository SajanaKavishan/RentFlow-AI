using Microsoft.EntityFrameworkCore;
using RentFlow.Api.Configuration;
using RentFlow.Api.Data;
using RentFlow.Api.DTOs.Payments;
using RentFlow.Api.Models;
using RentFlow.Api.Services;
using Xunit;

namespace RentFlow.Api.Tests.Services;

public sealed class StripePaymentFoundationTests
{
    [Fact]
    public async Task ManualCreation_UsesLegacyProviderAndNoStripeIdentifier()
    {
        await using var db = CreateDb();
        var tenantId = Guid.NewGuid();
        var schedule = await CreateScheduleAsync(db, tenantId);

        var response = await new PaymentService(db).CreateAsync(
            new CreatePaymentDto { RentScheduleItemId = schedule.Id, PaymentMethod = "BankTransfer" },
            tenantId);

        var payment = await db.Payments.SingleAsync();
        Assert.Equal(PaymentProvider.Manual, payment.Provider);
        Assert.Null(payment.StripePaymentIntentId);
        Assert.Equal(PaymentStatus.Pending, response.Status);
        Assert.Equal(schedule.Amount, payment.Amount);
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public async Task StripePayment_RejectsLegacySettlement(bool complete)
    {
        await using var db = CreateDb();
        var tenantId = Guid.NewGuid();
        var schedule = await CreateScheduleAsync(db, tenantId);
        var payment = NewPayment(schedule, tenantId, PaymentProvider.Stripe);
        db.Payments.Add(payment);
        await db.SaveChangesAsync();

        var service = new PaymentService(db);
        var exception = await Assert.ThrowsAsync<PaymentServiceException>(() =>
            complete ? service.CompleteAsync(payment.Id) : service.FailAsync(payment.Id));

        Assert.Equal(PaymentServiceError.Conflict, exception.Error);
        Assert.Equal(PaymentStatus.Pending, (await db.Payments.SingleAsync()).Status);
        Assert.Equal(RentScheduleStatus.Pending, (await db.RentScheduleItems.SingleAsync()).Status);
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public async Task LegacyManualPayment_CanStillBeSettled(bool complete)
    {
        await using var db = CreateDb();
        var tenantId = Guid.NewGuid();
        var schedule = await CreateScheduleAsync(db, tenantId);
        var payment = NewPayment(schedule, tenantId, PaymentProvider.Manual);
        db.Payments.Add(payment);
        await db.SaveChangesAsync();

        var service = new PaymentService(db);
        var response = complete
            ? await service.CompleteAsync(payment.Id)
            : await service.FailAsync(payment.Id);

        Assert.Equal(complete ? PaymentStatus.Completed : PaymentStatus.Failed, response.Status);
        Assert.Equal(complete ? RentScheduleStatus.Paid : RentScheduleStatus.Pending,
            schedule.Status);
    }

    [Fact]
    public void LkrOptions_EnforceSingleCurrencyAndExactDecimalMinorUnits()
    {
        var options = new StripePaymentOptions();
        Assert.True(options.HasValidCurrency);
        Assert.Equal("lkr", options.StripeCurrency);
        Assert.Equal(14_500_000L, StripePaymentOptions.ToStripeMinorUnits(145_000.00m));
        options.Currency = "USD";
        Assert.False(options.HasValidCurrency);
        Assert.Throws<ArgumentOutOfRangeException>(() =>
            StripePaymentOptions.ToStripeMinorUnits(1.001m));
        Assert.Throws<ArgumentOutOfRangeException>(() =>
            StripePaymentOptions.ToStripeMinorUnits(0m));
    }

    [Fact]
    public void EfModel_DefinesStripeFieldsAndPartialUniqueIndexes()
    {
        using var db = CreateDb();
        var entity = db.Model.FindEntityType(typeof(Payment))!;
        Assert.Equal(255, entity.FindProperty(nameof(Payment.StripePaymentIntentId))!.GetMaxLength());
        Assert.True(entity.FindProperty(nameof(Payment.StripePaymentIntentId))!.IsNullable);
        Assert.Equal(PaymentProvider.Manual,
            entity.FindProperty(nameof(Payment.Provider))!.GetDefaultValue());
        Assert.Contains(entity.GetIndexes(), index =>
            index.GetDatabaseName() == "IX_Payments_RentScheduleItemId_PendingStripe"
            && index.IsUnique
            && index.GetFilter() == "\"Provider\" = 1 AND \"Status\" = 0");
        Assert.Contains(entity.GetIndexes(), index =>
            index.Properties.Single().Name == nameof(Payment.StripePaymentIntentId)
            && index.IsUnique
            && index.GetFilter() == "\"StripePaymentIntentId\" IS NOT NULL");
        Assert.Contains(entity.GetIndexes(), index =>
            index.GetDatabaseName() == "IX_Payments_RentScheduleItemId_Completed"
            && index.IsUnique);
    }

    private static ApplicationDbContext CreateDb() => new(
        new DbContextOptionsBuilder<ApplicationDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString())
            .Options);

    private static async Task<RentScheduleItem> CreateScheduleAsync(
        ApplicationDbContext db, Guid tenantId)
    {
        var lease = new LeaseAgreement
        {
            RentalOfferId = Guid.NewGuid(),
            TenantId = tenantId,
            PropertyId = Guid.NewGuid(),
            MonthlyRent = 145_000m,
            SecurityDeposit = 290_000m,
            StartDate = new DateOnly(2026, 10, 1),
            EndDate = new DateOnly(2027, 9, 30),
            Status = LeaseAgreementStatus.Active
        };
        var schedule = new RentScheduleItem
        {
            LeaseAgreementId = lease.Id,
            DueDate = new DateOnly(2026, 10, 1),
            Amount = 145_000m,
            Status = RentScheduleStatus.Pending
        };
        db.LeaseAgreements.Add(lease);
        db.RentScheduleItems.Add(schedule);
        await db.SaveChangesAsync();
        return schedule;
    }

    private static Payment NewPayment(RentScheduleItem schedule, Guid tenantId,
        PaymentProvider provider) => new()
        {
            RentScheduleItemId = schedule.Id,
            TenantId = tenantId,
            Amount = schedule.Amount,
            PaymentMethod = provider == PaymentProvider.Stripe ? "Stripe" : "BankTransfer",
            Provider = provider,
            Status = PaymentStatus.Pending
        };
}
