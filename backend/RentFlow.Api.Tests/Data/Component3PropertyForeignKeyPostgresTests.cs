using Microsoft.EntityFrameworkCore;
using Npgsql;
using RentFlow.Api.Data;
using RentFlow.Api.Models;
using Xunit;

namespace RentFlow.Api.Tests.Data;

public sealed class Component3PropertyForeignKeyPostgresTests
{
    [PostgreSqlFact]
    public async Task Migrations_EnforceComponent3PropertyForeignKeys()
    {
        var configuredConnectionString =
            Environment.GetEnvironmentVariable("RENTFLOW_TEST_POSTGRES_CONNECTION_STRING")!;
        var adminConnectionString =
            new NpgsqlConnectionStringBuilder(configuredConnectionString);
        if (adminConnectionString.Database?.StartsWith(
                "rentflow_component3_test",
                StringComparison.OrdinalIgnoreCase) != true)
        {
            throw new InvalidOperationException(
                "The PostgreSQL FK test only runs against a database named with the rentflow_component3_test prefix.");
        }

        var schema = $"component3_fk_{Guid.NewGuid():N}";
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
        Guid offerPropertyId;
        Guid leasePropertyId;

        try
        {
            await using (var dbContext = new ApplicationDbContext(options))
            {
                await dbContext.Database.MigrateAsync();

                var offerProperty = CreateProperty();
                var leaseProperty = CreateProperty();
                offerPropertyId = offerProperty.Id;
                leasePropertyId = leaseProperty.Id;
                var offerApplication = CreateApplication(offerProperty.Id);
                var leaseApplication = CreateApplication(leaseProperty.Id);
                dbContext.Users.AddRange(
                    CreateLandlord(offerProperty.LandlordId),
                    CreateLandlord(leaseProperty.LandlordId));
                dbContext.Properties.AddRange(offerProperty, leaseProperty);
                dbContext.RentalApplications.AddRange(offerApplication, leaseApplication);
                await dbContext.SaveChangesAsync();

                var validOffer = CreateOffer(
                    offerApplication.Id,
                    offerApplication.TenantId,
                    offerProperty.Id);
                var acceptedOffer = CreateOffer(
                    leaseApplication.Id,
                    leaseApplication.TenantId,
                    leaseProperty.Id,
                    RentalOfferStatus.Accepted);
                dbContext.RentalOffers.AddRange(validOffer, acceptedOffer);
                await dbContext.SaveChangesAsync();

                dbContext.RentalOffers.Add(CreateOffer(
                    offerApplication.Id,
                    offerApplication.TenantId,
                    Guid.NewGuid()));
                await Assert.ThrowsAsync<DbUpdateException>(
                    () => dbContext.SaveChangesAsync());
                dbContext.ChangeTracker.Clear();

                dbContext.LeaseAgreements.Add(CreateLease(
                    acceptedOffer,
                    Guid.NewGuid()));
                await Assert.ThrowsAsync<DbUpdateException>(
                    () => dbContext.SaveChangesAsync());
                dbContext.ChangeTracker.Clear();

                dbContext.LeaseAgreements.Add(CreateLease(
                    acceptedOffer,
                    leaseProperty.Id));
                await dbContext.SaveChangesAsync();
            }

            await using (var dbContext = new ApplicationDbContext(options))
            {
                var offerProperty = await dbContext.Properties.SingleAsync(
                    property => property.Id == offerPropertyId);
                dbContext.Properties.Remove(offerProperty);
                await Assert.ThrowsAsync<DbUpdateException>(
                    () => dbContext.SaveChangesAsync());
            }

            await using (var dbContext = new ApplicationDbContext(options))
            {
                var leaseProperty = await dbContext.Properties.SingleAsync(
                    property => property.Id == leasePropertyId);
                dbContext.Properties.Remove(leaseProperty);
                await Assert.ThrowsAsync<DbUpdateException>(
                    () => dbContext.SaveChangesAsync());
            }
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

    private static ApplicationUser CreateLandlord(Guid id) => new()
    {
        Id = id,
        FullName = "PostgreSQL Test Landlord",
        Email = $"{id:N}@example.test",
        NormalizedEmail = $"{id:N}@EXAMPLE.TEST".ToUpperInvariant(),
        PhoneNumber = "0000000000",
        PasswordHash = "test-only",
        Role = UserRole.Landlord,
        CreatedAt = DateTimeOffset.UtcNow,
        UpdatedAt = DateTimeOffset.UtcNow
    };

    private static Property CreateProperty() => new()
    {
        LandlordId = Guid.NewGuid(),
        Title = "PostgreSQL FK Test Property",
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

    private static RentalOffer CreateOffer(
        Guid applicationId,
        Guid tenantId,
        Guid propertyId,
        RentalOfferStatus status = RentalOfferStatus.Pending) => new()
    {
        RentalApplicationId = applicationId,
        TenantId = tenantId,
        PropertyId = propertyId,
        MonthlyRent = 1000m,
        SecurityDeposit = 1000m,
        ProposedStartDate = DateOnly.FromDateTime(DateTime.UtcNow.AddDays(30)),
        ProposedEndDate = DateOnly.FromDateTime(DateTime.UtcNow.AddYears(1)),
        ExpiresAt = DateTimeOffset.UtcNow.AddDays(7),
        Status = status
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
        Status = LeaseAgreementStatus.Pending
    };
}

public sealed class PostgreSqlFactAttribute : FactAttribute
{
    public PostgreSqlFactAttribute()
    {
        if (string.IsNullOrWhiteSpace(
                Environment.GetEnvironmentVariable("RENTFLOW_TEST_POSTGRES_CONNECTION_STRING")))
        {
            Skip = "Set RENTFLOW_TEST_POSTGRES_CONNECTION_STRING to a disposable PostgreSQL test database.";
        }
    }
}
