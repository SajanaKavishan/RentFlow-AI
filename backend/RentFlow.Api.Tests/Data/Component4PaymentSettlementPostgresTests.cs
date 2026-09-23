using Microsoft.EntityFrameworkCore;
using Npgsql;
using RentFlow.Api.Data;
using RentFlow.Api.Models;
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
}
