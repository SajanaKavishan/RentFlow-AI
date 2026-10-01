using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using Npgsql;
using RentFlow.Api.Configuration;
using RentFlow.Api.Data;
using RentFlow.Api.Models;
using RentFlow.Api.Services;
using RentFlow.Api.Services.Interfaces;
using Xunit;

namespace RentFlow.Api.Tests.Data;

public sealed class Component4PaymentSettlementPostgresTests
{
    [PostgreSqlFact]
    public async Task Migration_AllowsPaymentAttemptsButOnlyOneCompletedPaymentPerSchedule()
    {
        var configuredConnectionString =
            Environment.GetEnvironmentVariable("RENTFLOW_TEST_POSTGRES_CONNECTION_STRING")!;
        var adminConnectionString = new NpgsqlConnectionStringBuilder(configuredConnectionString);
        if (adminConnectionString.Database?.StartsWith(
                "rentflow_component3_test",
                StringComparison.OrdinalIgnoreCase) != true)
        {
            throw new InvalidOperationException(
                "The PostgreSQL payment test only runs against a database named with the rentflow_component3_test prefix.");
        }

        var schema = $"component4_payment_{Guid.NewGuid():N}";
        await using (var adminConnection = new NpgsqlConnection(adminConnectionString.ConnectionString))
        {
            await adminConnection.OpenAsync();
            await using var createSchema = adminConnection.CreateCommand();
            createSchema.CommandText = $"CREATE SCHEMA \"{schema}\"";
            await createSchema.ExecuteNonQueryAsync();
        }

        var schemaConnectionString = new NpgsqlConnectionStringBuilder(
            adminConnectionString.ConnectionString)
        {
            SearchPath = schema
        }.ConnectionString;
        var options = new DbContextOptionsBuilder<ApplicationDbContext>()
            .UseNpgsql(schemaConnectionString)
            .Options;

        try
        {
            await using var dbContext = new ApplicationDbContext(options);
            await dbContext.Database.MigrateAsync();

            var landlord = CreateLandlord();
            var property = CreateProperty(landlord.Id);
            var application = CreateApplication(property.Id);
            var offer = CreateOffer(application.Id, application.TenantId, property.Id);
            var lease = CreateLease(offer, property.Id);
            var schedule = CreateSchedule(lease.Id);
            dbContext.Users.Add(landlord);
            dbContext.Properties.Add(property);
            dbContext.RentalApplications.Add(application);
            dbContext.RentalOffers.Add(offer);
            dbContext.LeaseAgreements.Add(lease);
            dbContext.RentScheduleItems.Add(schedule);
            await dbContext.SaveChangesAsync();

            var legacyPaymentId = Guid.NewGuid();
            await dbContext.Database.ExecuteSqlInterpolatedAsync(
                $"INSERT INTO \"Payments\" (\"Id\", \"RentScheduleItemId\", \"TenantId\", \"Amount\", \"PaymentMethod\", \"Status\", \"CreatedAt\") VALUES ({legacyPaymentId}, {schedule.Id}, {offer.TenantId}, {schedule.Amount}, {"BankTransfer"}, {0}, {DateTimeOffset.UtcNow})");

            var legacyPayment = await dbContext.Payments.AsNoTracking()
                .SingleAsync(payment => payment.Id == legacyPaymentId);
            Assert.Equal(PaymentProvider.Manual, legacyPayment.Provider);
            Assert.Null(legacyPayment.StripePaymentIntentId);

            dbContext.Payments.AddRange(
                CreatePayment(schedule, PaymentStatus.Pending),
                CreatePayment(schedule, PaymentStatus.Pending),
                CreatePayment(schedule, PaymentStatus.Failed),
                CreatePayment(schedule, PaymentStatus.Failed),
                CreatePayment(schedule, PaymentStatus.Completed));
            await dbContext.SaveChangesAsync();

            var completedPayments = await dbContext.Payments
                .AsNoTracking()
                .CountAsync(payment =>
                    payment.RentScheduleItemId == schedule.Id &&
                    payment.Status == PaymentStatus.Completed);
            Assert.Equal(1, completedPayments);

            dbContext.Payments.Add(CreatePayment(schedule, PaymentStatus.Completed));
            await Assert.ThrowsAsync<DbUpdateException>(
                () => dbContext.SaveChangesAsync());
            dbContext.ChangeTracker.Clear();

            var stripeSchedule = CreateSchedule(lease.Id);
            stripeSchedule.DueDate = stripeSchedule.DueDate.AddMonths(1);
            var otherSchedule = CreateSchedule(lease.Id);
            otherSchedule.DueDate = otherSchedule.DueDate.AddMonths(2);
            dbContext.RentScheduleItems.AddRange(stripeSchedule, otherSchedule);
            await dbContext.SaveChangesAsync();

            var firstStripeAttempt = CreatePayment(stripeSchedule, PaymentStatus.Pending);
            firstStripeAttempt.Provider = PaymentProvider.Stripe;
            firstStripeAttempt.StripePaymentIntentId = "pi_test_first";
            dbContext.Payments.Add(firstStripeAttempt);
            await dbContext.SaveChangesAsync();
            Assert.Equal("pi_test_first", (await dbContext.Payments.AsNoTracking()
                .SingleAsync(payment => payment.Id == firstStripeAttempt.Id)).StripePaymentIntentId);

            var duplicateActiveAttempt = CreatePayment(stripeSchedule, PaymentStatus.Pending);
            duplicateActiveAttempt.Provider = PaymentProvider.Stripe;
            duplicateActiveAttempt.StripePaymentIntentId = "pi_test_second";
            dbContext.Payments.Add(duplicateActiveAttempt);
            await Assert.ThrowsAsync<DbUpdateException>(() => dbContext.SaveChangesAsync());
            dbContext.ChangeTracker.Clear();

            var duplicateIntent = CreatePayment(otherSchedule, PaymentStatus.Pending);
            duplicateIntent.Provider = PaymentProvider.Stripe;
            duplicateIntent.StripePaymentIntentId = firstStripeAttempt.StripePaymentIntentId;
            dbContext.Payments.Add(duplicateIntent);
            await Assert.ThrowsAsync<DbUpdateException>(() => dbContext.SaveChangesAsync());
            dbContext.ChangeTracker.Clear();

            var persistedAttempt = await dbContext.Payments.SingleAsync(
                payment => payment.Id == firstStripeAttempt.Id);
            persistedAttempt.Status = PaymentStatus.Failed;
            await dbContext.SaveChangesAsync();
            var retry = CreatePayment(stripeSchedule, PaymentStatus.Pending);
            retry.Provider = PaymentProvider.Stripe;
            retry.StripePaymentIntentId = "pi_test_retry";
            dbContext.Payments.Add(retry);
            await dbContext.SaveChangesAsync();
            Assert.Equal(2, await dbContext.Payments.CountAsync(payment =>
                payment.RentScheduleItemId == stripeSchedule.Id
                && payment.Provider == PaymentProvider.Stripe));

            var settlementSchedule = CreateSchedule(lease.Id);
            settlementSchedule.DueDate = settlementSchedule.DueDate.AddMonths(3);
            dbContext.RentScheduleItems.Add(settlementSchedule);
            await dbContext.SaveChangesAsync();
            var settlementPayment = CreatePayment(settlementSchedule, PaymentStatus.Pending);
            settlementPayment.TenantId = offer.TenantId;
            settlementPayment.Provider = PaymentProvider.Stripe;
            settlementPayment.StripePaymentIntentId = "pi_test_verified_settlement";
            dbContext.Payments.Add(settlementPayment);
            await dbContext.SaveChangesAsync();

            var intent = new StripePaymentIntentResult(
                settlementPayment.StripePaymentIntentId, null, "succeeded",
                (long)(settlementPayment.Amount * 100m), "lkr",
                new Dictionary<string, string>
                {
                    ["rentflowPaymentId"] = settlementPayment.Id.ToString("D"),
                    ["rentScheduleItemId"] = settlementSchedule.Id.ToString("D"),
                    ["tenantId"] = settlementPayment.TenantId.ToString("D")
                });
            var stripeService = new StripePaymentService(
                dbContext, new SettlementGateway(intent),
                Options.Create(new StripePaymentOptions()));
            var firstSettlement = await stripeService.GetStatusAsync(
                settlementPayment.Id, settlementPayment.TenantId);
            var secondSettlement = await stripeService.GetStatusAsync(
                settlementPayment.Id, settlementPayment.TenantId);
            Assert.Equal(PaymentStatus.Completed, firstSettlement.PaymentStatus);
            Assert.Equal(firstSettlement.PaidAt, secondSettlement.PaidAt);
            dbContext.ChangeTracker.Clear();
            Assert.Equal(PaymentStatus.Completed,
                (await dbContext.Payments.SingleAsync(payment =>
                    payment.Id == settlementPayment.Id)).Status);
            Assert.Equal(RentScheduleStatus.Paid,
                (await dbContext.RentScheduleItems.SingleAsync(item =>
                    item.Id == settlementSchedule.Id)).Status);

            var concurrentSchedule = CreateSchedule(lease.Id);
            concurrentSchedule.DueDate = concurrentSchedule.DueDate.AddMonths(4);
            dbContext.RentScheduleItems.Add(concurrentSchedule);
            await dbContext.SaveChangesAsync();
            var concurrentPayment = CreatePayment(concurrentSchedule, PaymentStatus.Pending);
            concurrentPayment.TenantId = offer.TenantId;
            concurrentPayment.Provider = PaymentProvider.Stripe;
            concurrentPayment.StripePaymentIntentId = "pi_test_concurrent_settlement";
            dbContext.Payments.Add(concurrentPayment);
            await dbContext.SaveChangesAsync();

            var concurrentIntent = new StripePaymentIntentResult(
                concurrentPayment.StripePaymentIntentId, null, "succeeded",
                (long)(concurrentPayment.Amount * 100m), "lkr",
                new Dictionary<string, string>
                {
                    ["rentflowPaymentId"] = concurrentPayment.Id.ToString("D"),
                    ["rentScheduleItemId"] = concurrentSchedule.Id.ToString("D"),
                    ["tenantId"] = concurrentPayment.TenantId.ToString("D")
                });
            await using var webhookContext = new ApplicationDbContext(options);
            await using var statusContext = new ApplicationDbContext(options);
            var webhookService = new StripePaymentService(
                webhookContext, new SettlementGateway(concurrentIntent),
                Options.Create(new StripePaymentOptions()));
            var statusService = new StripePaymentService(
                statusContext, new SettlementGateway(concurrentIntent),
                Options.Create(new StripePaymentOptions()));

            await Task.WhenAll(
                webhookService.ProcessWebhookAsync(concurrentIntent.Id),
                statusService.GetStatusAsync(concurrentPayment.Id, concurrentPayment.TenantId));

            dbContext.ChangeTracker.Clear();
            var settledPayment = await dbContext.Payments.AsNoTracking()
                .SingleAsync(payment => payment.Id == concurrentPayment.Id);
            Assert.Equal(PaymentStatus.Completed, settledPayment.Status);
            Assert.NotNull(settledPayment.PaidAt);
            Assert.Equal(RentScheduleStatus.Paid,
                (await dbContext.RentScheduleItems.AsNoTracking().SingleAsync(item =>
                    item.Id == concurrentSchedule.Id)).Status);
            Assert.Equal(1, await dbContext.Payments.CountAsync(payment =>
                payment.RentScheduleItemId == concurrentSchedule.Id
                && payment.Status == PaymentStatus.Completed));

            await webhookService.ProcessWebhookAsync(concurrentIntent.Id);
            Assert.Equal(settledPayment.PaidAt,
                (await dbContext.Payments.AsNoTracking().SingleAsync(payment =>
                    payment.Id == concurrentPayment.Id)).PaidAt);
        }
        finally
        {
            await using var adminConnection = new NpgsqlConnection(adminConnectionString.ConnectionString);
            await adminConnection.OpenAsync();
            await using var dropSchema = adminConnection.CreateCommand();
            dropSchema.CommandText = $"DROP SCHEMA IF EXISTS \"{schema}\" CASCADE";
            await dropSchema.ExecuteNonQueryAsync();
        }
    }

    private static ApplicationUser CreateLandlord()
    {
        var id = Guid.NewGuid();
        var email = $"{id:N}@example.test";
        return new ApplicationUser
        {
            Id = id,
            FullName = "PostgreSQL Payment Test Landlord",
            Email = email,
            NormalizedEmail = email.ToUpperInvariant(),
            PhoneNumber = "0000000000",
            PasswordHash = "test-only",
            Role = UserRole.Landlord,
            CreatedAt = DateTimeOffset.UtcNow,
            UpdatedAt = DateTimeOffset.UtcNow
        };
    }

    private static Property CreateProperty(Guid landlordId) => new()
    {
        LandlordId = landlordId,
        Title = "PostgreSQL Payment Test Property",
        Description = "Test property",
        Address = "Test address",
        City = "Test city",
        MonthlyRent = 1000m,
        Bedrooms = 1,
        Bathrooms = 1
    };

    private static RentalApplication CreateApplication(Guid propertyId) => new()
    {
        TenantId = Guid.NewGuid(),
        PropertyId = propertyId,
        MoveInDate = DateOnly.FromDateTime(DateTime.UtcNow.AddDays(30)),
        MonthlyIncome = 5000m,
        Occupation = "Test occupation",
        NumberOfOccupants = 1,
        Status = RentalApplicationStatus.Approved
    };

    private static RentalOffer CreateOffer(Guid applicationId, Guid tenantId, Guid propertyId) => new()
    {
        RentalApplicationId = applicationId,
        TenantId = tenantId,
        PropertyId = propertyId,
        MonthlyRent = 1000m,
        SecurityDeposit = 1000m,
        ProposedStartDate = DateOnly.FromDateTime(DateTime.UtcNow.AddDays(30)),
        ProposedEndDate = DateOnly.FromDateTime(DateTime.UtcNow.AddYears(1)),
        ExpiresAt = DateTimeOffset.UtcNow.AddDays(7),
        Status = RentalOfferStatus.Accepted
    };

    private static LeaseAgreement CreateLease(RentalOffer offer, Guid propertyId) => new()
    {
        RentalOfferId = offer.Id,
        TenantId = offer.TenantId,
        PropertyId = propertyId,
        MonthlyRent = offer.MonthlyRent,
        SecurityDeposit = offer.SecurityDeposit,
        StartDate = offer.ProposedStartDate,
        EndDate = offer.ProposedEndDate,
        Status = LeaseAgreementStatus.Active
    };

    private static RentScheduleItem CreateSchedule(Guid leaseAgreementId) => new()
    {
        LeaseAgreementId = leaseAgreementId,
        DueDate = DateOnly.FromDateTime(DateTime.UtcNow.AddDays(30)),
        Amount = 1000m,
        Status = RentScheduleStatus.Pending
    };

    private static Payment CreatePayment(RentScheduleItem schedule, PaymentStatus status) => new()
    {
        RentScheduleItemId = schedule.Id,
        TenantId = Guid.NewGuid(),
        Amount = schedule.Amount,
        PaymentMethod = "BankTransfer",
        Status = status
    };

    private sealed class SettlementGateway(StripePaymentIntentResult intent)
        : IStripePaymentGateway
    {
        public Task<StripePaymentIntentResult> CreateAsync(
            StripePaymentIntentRequest request,
            CancellationToken cancellationToken = default) =>
            throw new InvalidOperationException("Settlement test must not create an intent.");

        public Task<StripePaymentIntentResult> RetrieveAsync(
            string paymentIntentId,
            CancellationToken cancellationToken = default)
        {
            Assert.Equal(intent.Id, paymentIntentId);
            return Task.FromResult(intent);
        }
    }
}
