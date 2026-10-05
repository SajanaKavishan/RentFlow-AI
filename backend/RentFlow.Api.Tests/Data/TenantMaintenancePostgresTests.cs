using System.Collections.Concurrent;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using Microsoft.Extensions.Logging.Abstractions;
using Npgsql;
using RentFlow.Api.Data;
using RentFlow.Api.Models;
using RentFlow.Api.Services;
using RentFlow.Api.Services.Interfaces;
using RentFlow.Api.Tests.Services;
using Xunit;

namespace RentFlow.Api.Tests.Data;

public sealed class TenantMaintenancePostgresTests
{
    [PostgreSqlFact]
    public async Task Migration_BackfillsReferenceAndPreservesLegacyRowsAndNullableAccess()
    {
        await using var database = await TestDatabase.CreateAsync();
        await using var context = database.Context();
        var migrations = context.Database.GetMigrations().ToArray();
        var migrator = context.GetService<IMigrator>();
        await migrator.MigrateAsync(migrations[^2]);
        var id = Guid.NewGuid();
        var tenant = Guid.NewGuid();
        var property = Guid.NewGuid();
        var description = new string('x', 3500);
        await context.Database.ExecuteSqlInterpolatedAsync($"INSERT INTO \"MaintenanceRequests\" (\"Id\",\"TenantId\",\"PropertyId\",\"Title\",\"Description\",\"Category\",\"Priority\",\"Status\",\"CreatedAt\") VALUES ({id},{tenant},{property},{"Legacy request"},{description},0,0,0,{DateTimeOffset.UtcNow})");
        await using var migrated = database.Context();
        await migrated.Database.MigrateAsync();
        var service = new MaintenanceRequestService(migrated);
        var legacy = (await service.GetByIdAsync(id))!;
        Assert.Equal(description, legacy.Description);
        Assert.Null(legacy.PreferredAccessWindow);
        Assert.Equal(MaintenancePriority.Low, legacy.Priority);
        Assert.Equal(MaintenanceReferenceCode.FromId(id), legacy.ReferenceCode);
        Assert.Matches("^MR-[A-F0-9]{16}$", legacy.ReferenceCode);
        Assert.Equal(legacy.ReferenceCode, (await service.GetByTenantAsync(tenant)).Single().ReferenceCode);
        var invalid = await Assert.ThrowsAsync<PostgresException>(() => migrated.Database.ExecuteSqlInterpolatedAsync($"UPDATE \"MaintenanceRequests\" SET \"PreferredAccessWindow\" = {"Night"} WHERE \"Id\" = {id}"));
        Assert.Equal(PostgresErrorCodes.CheckViolation, invalid.SqlState);
        var altered = await Assert.ThrowsAsync<PostgresException>(() => migrated.Database.ExecuteSqlInterpolatedAsync($"UPDATE \"MaintenanceRequests\" SET \"ReferenceCode\" = {"MR-CLIENTCOUNTER"} WHERE \"Id\" = {id}"));
        Assert.Equal("428C9", altered.SqlState);
        Assert.Equal(legacy.ReferenceCode, (await service.GetByIdAsync(id))!.ReferenceCode);
    }

    [PostgreSqlFact]
    public async Task ConcurrentCreation_PersistsUniqueReferencesAndAccessWindows()
    {
        await using var database = await TestDatabase.CreateAsync();
        var tenant = Guid.NewGuid();
        var property = Guid.NewGuid();
        await using (var setup = database.Context())
        {
            await setup.Database.MigrateAsync();
            await MaintenanceTenancyFixture.SeedAsync(setup, tenant, property);
        }
        var requests = await Task.WhenAll(Enumerable.Range(0, 20).Select(async _ =>
        {
            await using var context = database.Context();
            var input = TenantMaintenanceWorkflowTests.Request();
            input.PropertyId = property;
            input.Category = MaintenanceCategory.Hvac;
            input.PreferredAccessWindow = PreferredAccessWindow.Evening;
            return await new MaintenanceRequestService(context).CreateAsync(tenant, input);
        }));
        Assert.Equal(20, requests.Select(item => item.ReferenceCode).Distinct().Count());
        await using var verify = database.Context();
        var persisted = await verify.MaintenanceRequests.AsNoTracking().ToListAsync();
        Assert.Equal(20, persisted.Count);
        Assert.All(persisted, item =>
        {
            Assert.Equal(MaintenanceReferenceCode.FromId(item.Id), item.ReferenceCode);
            Assert.Equal(PreferredAccessWindow.Evening, item.PreferredAccessWindow);
            Assert.Equal(MaintenanceCategory.Hvac, item.Category);
        });
        Assert.True(verify.Model.FindEntityType(typeof(MaintenanceRequest))!.GetIndexes().Single(index => index.Properties.Count == 1 && index.Properties[0].Name == nameof(MaintenanceRequest.ReferenceCode)).IsUnique);
    }

    [PostgreSqlFact]
    public async Task ConcurrentUploads_EnforceFivePhotosAndTenantOwnership()
    {
        await using var database = await TestDatabase.CreateAsync();
        var tenant = Guid.NewGuid();
        var input = TenantMaintenanceWorkflowTests.Request();
        Guid requestId;
        await using (var setup = database.Context())
        {
            await setup.Database.MigrateAsync();
            await MaintenanceTenancyFixture.SeedAsync(setup, tenant, input.PropertyId);
            requestId = (await new MaintenanceRequestService(setup).CreateAsync(tenant, input)).Id;
        }
        var storage = new TestStorage();
        var results = await Task.WhenAll(Enumerable.Range(0, 6).Select(async index =>
        {
            await using var context = database.Context();
            var service = new MaintenanceAttachmentService(context, storage, NullLogger<MaintenanceAttachmentService>.Instance);
            using var content = new MemoryStream([1, 2, 3]);
            try
            {
                await service.UploadAsync(requestId, tenant, content, $"photo-{index}.jpg", "image/jpeg", 3, null);
                return true;
            }
            catch (MaintenanceRequestServiceException error)
            {
                Assert.Equal(MaintenanceRequestServiceError.Validation, error.Error);
                return false;
            }
        }));
        Assert.Equal(5, results.Count(success => success));
        Assert.Equal(5, storage.Uploads.Count);
        await using var verify = database.Context();
        Assert.Equal(5, await verify.MaintenanceAttachments.CountAsync());
        var unauthorized = new MaintenanceAttachmentService(verify, storage, NullLogger<MaintenanceAttachmentService>.Instance);
        using var file = new MemoryStream([1, 2, 3]);
        var rejected = await Assert.ThrowsAsync<MaintenanceRequestServiceException>(() => unauthorized.UploadAsync(requestId, Guid.NewGuid(), file, "other.jpg", "image/jpeg", 3, null));
        Assert.Equal(MaintenanceRequestServiceError.NotFound, rejected.Error);
        Assert.Equal(5, storage.Uploads.Count);
    }

    private sealed class TestStorage : IFileStorageService
    {
        internal ConcurrentBag<string> Uploads { get; } = [];
        public async Task UploadAsync(Stream content, string storageKey, string contentType, CancellationToken cancellationToken = default) { await Task.Delay(20, cancellationToken); Uploads.Add(storageKey); }
        public Task DeleteAsync(string storageKey, CancellationToken cancellationToken = default) => Task.CompletedTask;
        public Task<byte[]> DownloadBytesAsync(string storageKey, long maximumBytes, CancellationToken cancellationToken = default) => Task.FromResult(new byte[] { 1, 2, 3 });
        public Task<string> GenerateDownloadUrlAsync(string storageKey, string originalFileName, string contentType, TimeSpan lifetime) => Task.FromResult("https://test.invalid/photo.jpg");
        public Task<string> GenerateInlineUrlAsync(string storageKey, string contentType, TimeSpan lifetime) => Task.FromResult("https://test.invalid/photo.jpg");
    }

    private sealed class TestDatabase(string connection, string schema) : IAsyncDisposable
    {
        internal ApplicationDbContext Context() => new(new DbContextOptionsBuilder<ApplicationDbContext>().UseNpgsql(new NpgsqlConnectionStringBuilder(connection) { SearchPath = schema }.ConnectionString, options => options.MigrationsHistoryTable("__EFMigrationsHistory", schema)).Options);

        internal static async Task<TestDatabase> CreateAsync()
        {
            var connection = Environment.GetEnvironmentVariable("RENTFLOW_TEST_POSTGRES_CONNECTION_STRING")!;
            if (new NpgsqlConnectionStringBuilder(connection).Database?.StartsWith("rentflow_component3_test", StringComparison.OrdinalIgnoreCase) != true)
                throw new InvalidOperationException("Maintenance PostgreSQL tests require a disposable rentflow_component3_test database.");
            var schema = $"maintenance_task2_{Guid.NewGuid():N}";
            await using var admin = new NpgsqlConnection(connection);
            await admin.OpenAsync();
            await using var command = new NpgsqlCommand($"CREATE SCHEMA \"{schema}\"", admin);
            await command.ExecuteNonQueryAsync();
            return new TestDatabase(connection, schema);
        }

        public async ValueTask DisposeAsync()
        {
            await using var admin = new NpgsqlConnection(connection);
            await admin.OpenAsync();
            await using var command = new NpgsqlCommand($"DROP SCHEMA \"{schema}\" CASCADE", admin);
            await command.ExecuteNonQueryAsync();
        }
    }
}
