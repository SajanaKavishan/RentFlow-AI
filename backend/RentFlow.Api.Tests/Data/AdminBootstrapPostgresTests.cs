using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Npgsql;
using RentFlow.Api.Data;
using RentFlow.Api.Models;
using RentFlow.Api.Services;
using Xunit;

namespace RentFlow.Api.Tests.Data;

public sealed class AdminBootstrapPostgresTests
{
    [PostgreSqlFact]
    public async Task ConcurrentBootstrapAttempts_CreateExactlyOneAdmin()
    {
        var configuredConnectionString =
            Environment.GetEnvironmentVariable("RENTFLOW_TEST_POSTGRES_CONNECTION_STRING")!;
        var adminConnectionString = new NpgsqlConnectionStringBuilder(configuredConnectionString);
        if (adminConnectionString.Database?.StartsWith(
                "rentflow_component3_test",
                StringComparison.OrdinalIgnoreCase) != true)
        {
            throw new InvalidOperationException(
                "The PostgreSQL bootstrap test only runs against a database named with the rentflow_component3_test prefix.");
        }

        var schema = $"admin_bootstrap_{Guid.NewGuid():N}";
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
            await using (var migrationContext = new ApplicationDbContext(options))
            {
                await migrationContext.Database.MigrateAsync();
            }

            var ready = new TaskCompletionSource(
                TaskCreationOptions.RunContinuationsAsynchronously);
            var attempts = Enumerable.Range(0, 6)
                .Select(index => AttemptBootstrapAsync(index, options, ready.Task))
                .ToArray();

            ready.SetResult();
            var results = await Task.WhenAll(attempts);

            Assert.Single(results, result => result is null);
            Assert.All(
                results.Where(result => result is not null),
                error => Assert.Equal(AdminBootstrapError.AlreadyCompleted, error));

            await using var verificationContext = new ApplicationDbContext(options);
            Assert.Equal(
                1,
                await verificationContext.Users.CountAsync(
                    user => user.Role == UserRole.Admin));
            Assert.Equal(1, await verificationContext.AdminBootstrapRecords.CountAsync());
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

    private static async Task<AdminBootstrapError?> AttemptBootstrapAsync(
        int index,
        DbContextOptions<ApplicationDbContext> options,
        Task start)
    {
        await start;
        await using var context = new ApplicationDbContext(options);
        var service = new AdminBootstrapService(
            context,
            new PasswordHasher<ApplicationUser>(),
            TimeProvider.System);

        try
        {
            await service.BootstrapAsync(
                $"Admin {index}",
                $"admin{index}@example.test",
                $"+9477000000{index}",
                "Secure1!Password");
            return null;
        }
        catch (AdminBootstrapException exception)
        {
            return exception.Error;
        }
    }
}
