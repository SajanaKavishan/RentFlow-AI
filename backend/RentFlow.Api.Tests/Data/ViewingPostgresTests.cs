using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using Npgsql;
using RentFlow.Api.Data;
using RentFlow.Api.DTOs.Viewings;
using RentFlow.Api.DTOs.RentalApplications;
using RentFlow.Api.Models;
using RentFlow.Api.Services;
using RentFlow.Api.Tests.Services;
using Xunit;

namespace RentFlow.Api.Tests.Data;

public sealed class ViewingPostgresTests
{
    [PostgreSqlFact]
    public async Task RentalApplicationEligibility_QueriesRealHistoryAndSerializesCompetingCreates()
    {
        await using var database = new Database(); await database.CreateAsync();
        await using var setup = new ApplicationDbContext(database.Options);
        var (property, slot) = await SeedAsync(setup);
        var tenant = new ApplicationUser { FullName = "Eligible tenant", Email = $"{Guid.NewGuid():N}@example.test",
            NormalizedEmail = Guid.NewGuid().ToString("N"), PhoneNumber = "0000000000", PasswordHash = "test-only", Role = UserRole.Tenant };
        setup.Add(tenant);
        setup.AddRange(new ViewingRequest { TenantId = tenant.Id, PropertyId = property.Id, Status = ViewingStatus.Completed, RequestedDateTime = slot.RequestedDateTime },
            new ViewingRequest { TenantId = tenant.Id, PropertyId = property.Id, Status = ViewingStatus.Completed, RequestedDateTime = slot.RequestedDateTime.AddDays(-365) });
        await setup.SaveChangesAsync();
        var service = new RentalApplicationService(setup);
        Assert.True((await service.GetEligibilityAsync(tenant.Id, property.Id)).CanApply);
        Assert.Equal(property.Id, Assert.Single(await service.GetEligiblePropertiesAsync(tenant.Id)).Id);
        Assert.Empty(await service.GetEligiblePropertiesAsync(Guid.NewGuid()));
        await using var blocker = new ApplicationDbContext(database.Options);
        await using var held = await blocker.Database.BeginTransactionAsync();
        await blocker.Database.ExecuteSqlInterpolatedAsync($"SELECT 1 FROM \"Properties\" WHERE \"Id\" = {property.Id} FOR UPDATE");
        await using var db1 = new ApplicationDbContext(database.Options);
        await using var db2 = new ApplicationDbContext(database.Options);
        async Task<bool> Create(ApplicationDbContext context)
        {
            try
            {
                await new RentalApplicationService(context).CreateAsync(tenant.Id, new CreateRentalApplicationDto
                { PropertyId = property.Id, MoveInDate = DateOnly.FromDateTime(DateTime.UtcNow.AddDays(30)), MonthlyIncome = 100000,
                    Occupation = "Engineer", NumberOfOccupants = 1 });
                return true;
            }
            catch (RentalApplicationServiceException error)
            { Assert.Equal(RentalApplicationServiceError.Conflict, error.Error); return false; }
        }
        var first = Create(db1); var second = Create(db2);
        await Task.Delay(200);
        Assert.False(first.IsCompleted); Assert.False(second.IsCompleted);
        await held.CommitAsync();
        Assert.Single(await Task.WhenAll(first, second).WaitAsync(TimeSpan.FromSeconds(20)), success => success);
        var draft = await setup.RentalApplications.AsNoTracking().SingleAsync();
        Assert.Equal(draft.Id, (await service.GetEligibilityAsync(tenant.Id, property.Id)).ExistingApplicationId);
        Assert.Empty(await service.GetEligiblePropertiesAsync(tenant.Id));
    }

    private sealed class Database : IAsyncDisposable
    {
        private readonly string admin;
        private readonly string schema = $"viewing_{Guid.NewGuid():N}";
        public DbContextOptions<ApplicationDbContext> Options { get; }
        public Database()
        {
            var builder = new NpgsqlConnectionStringBuilder(Environment.GetEnvironmentVariable("RENTFLOW_TEST_POSTGRES_CONNECTION_STRING"));
            if (builder.Database?.StartsWith("rentflow_component3_test", StringComparison.OrdinalIgnoreCase) != true)
                throw new InvalidOperationException("Viewing tests require the rentflow_component3_test disposable database prefix.");
            admin = builder.ConnectionString;
            builder.SearchPath = schema;
            Options = new DbContextOptionsBuilder<ApplicationDbContext>().UseNpgsql(builder.ConnectionString,
                options => options.MigrationsHistoryTable("__EFMigrationsHistory", schema)).Options;
        }
        public async Task CreateAsync()
        {
            await using var connection = new NpgsqlConnection(admin); await connection.OpenAsync();
            await using var command = connection.CreateCommand(); command.CommandText = $"CREATE SCHEMA \"{schema}\"";
            await command.ExecuteNonQueryAsync();
        }
        public async ValueTask DisposeAsync()
        {
            await using var connection = new NpgsqlConnection(admin); await connection.OpenAsync();
            await using var command = connection.CreateCommand(); command.CommandText = $"DROP SCHEMA IF EXISTS \"{schema}\" CASCADE";
            await command.ExecuteNonQueryAsync();
        }
    }

    [PostgreSqlFact]
    public async Task Migration_BackfillsOnlyDuration_AndCreatesNoHistoricalWindows()
    {
        await using var database = new Database(); await database.CreateAsync();
        await using var db = new ApplicationDbContext(database.Options);
        var migrator = db.GetService<IMigrator>();
        await migrator.MigrateAsync("20260930120050_AddPropertyListingPreferencesAndCanonicalAmenities");
        var id = Guid.NewGuid(); var tenant = Guid.NewGuid(); var property = Guid.NewGuid();
        var instant = new DateTimeOffset(2026, 1, 1, 0, 0, 0, TimeSpan.Zero);
        await db.Database.ExecuteSqlInterpolatedAsync($"INSERT INTO \"ViewingRequests\" (\"Id\",\"TenantId\",\"PropertyId\",\"RequestedDateTime\",\"Status\",\"CreatedAt\") VALUES ({id},{tenant},{property},{instant},{1},{instant})");
        await using var migrated = new ApplicationDbContext(database.Options);
        await migrated.Database.MigrateAsync();
        var stored = await migrated.ViewingRequests.SingleAsync();
        Assert.Equal(60, stored.DurationMinutes); Assert.Equal(instant, stored.RequestedDateTime);
        Assert.Equal(ViewingStatus.Approved, stored.Status); Assert.Empty(migrated.PropertyViewingAvailabilities);
    }

    private static async Task<(Property Property, ViewingSlotDto Slot)> SeedAsync(ApplicationDbContext db)
    {
        await db.Database.MigrateAsync();
        var landlord = new ApplicationUser { Id = Guid.NewGuid(), FullName = "Viewing test landlord", Email = $"{Guid.NewGuid():N}@example.test",
            NormalizedEmail = Guid.NewGuid().ToString("N"), PhoneNumber = "0000000000", PasswordHash = "test-only", Role = UserRole.Landlord };
        var property = new Property { LandlordId = landlord.Id, Title = "Viewing home", Description = "Test", Address = "Test", City = "Colombo", MonthlyRent = 100000, Bedrooms = 1, Bathrooms = 1 };
        db.Add(landlord); db.Add(property); await db.SaveChangesAsync();
        var date = DateOnly.FromDateTime(DateTime.UtcNow.AddDays(2));
        var service = new ViewingAvailabilityService(db);
        await service.SaveAsync(property.Id, landlord.Id, new ViewingAvailabilityDto { Windows = [new()
            { DayOfWeek = (int)date.DayOfWeek, IsEnabled = true, StartTime = new(9, 0), EndTime = new(17, 0) }] });
        return (property, (await service.GetSlotsAsync(property.Id, date)).Slots[0]);
    }

    [PostgreSqlFact]
    public async Task CompetingApprovals_WaitForPropertyLock_ThenOnlyOneOverlappingRequestWins()
    {
        await using var database = new Database(); await database.CreateAsync();
        await using var setup = new ApplicationDbContext(database.Options);
        var (property, slot) = await SeedAsync(setup);
        var first = new ViewingRequest { PropertyId = property.Id, TenantId = Guid.NewGuid(), RequestedDateTime = slot.RequestedDateTime, DurationMinutes = 60 };
        var second = new ViewingRequest { PropertyId = property.Id, TenantId = Guid.NewGuid(), RequestedDateTime = slot.RequestedDateTime.AddMinutes(30), DurationMinutes = 60 };
        foreach (var tenantId in new[] { first.TenantId, second.TenantId })
            setup.Add(new ApplicationUser { Id = tenantId, FullName = "Test tenant", Email = $"{tenantId:N}@example.test",
                NormalizedEmail = $"{tenantId:N}@EXAMPLE.TEST", PhoneNumber = "0000000000", PasswordHash = "test-only", Role = UserRole.Tenant });
        setup.AddRange(first, second); await setup.SaveChangesAsync();
        await using var blocker = new ApplicationDbContext(database.Options);
        await using var held = await blocker.Database.BeginTransactionAsync();
        await blocker.Database.ExecuteSqlInterpolatedAsync($"SELECT 1 FROM \"Properties\" WHERE \"Id\" = {property.Id} FOR UPDATE");
        await using var db1 = new ApplicationDbContext(database.Options);
        await using var db2 = new ApplicationDbContext(database.Options);
        async Task<bool> Approve(ApplicationDbContext context, Guid id)
        {
            try { await new ViewingService(context).ApproveAsync(id); return true; }
            catch (ViewingServiceException error) { Assert.Equal(ViewingServiceError.Conflict, error.Error); return false; }
        }
        var a = Approve(db1, first.Id); var b = Approve(db2, second.Id);
        await Task.Delay(200);
        Assert.False(a.IsCompleted); Assert.False(b.IsCompleted);
        await held.CommitAsync();
        var results = await Task.WhenAll(a, b).WaitAsync(TimeSpan.FromSeconds(20));
        Assert.Single(results, success => success);
        setup.ChangeTracker.Clear();
        Assert.Equal(1, await setup.ViewingRequests.CountAsync(v => v.Status == ViewingStatus.Approved));
        Assert.Equal(1, await setup.ViewingRequests.CountAsync(v => v.Status == ViewingStatus.Pending));
        Assert.Equal(1, await setup.Notifications.CountAsync(n => n.EventType == "viewing.approved"));
        var day = DateOnly.FromDateTime(TimeZoneInfo.ConvertTime(slot.RequestedDateTime,
            ViewingAvailabilityService.ResolveZone(property.ViewingTimeZoneId)).DateTime);
        var availability = new ViewingAvailabilityService(setup);
        var enriched = await availability.GetSlotsAsync(property.Id, day, includeUnavailable: true);
        Assert.Equal(8, enriched.Slots.Count);
        var blocked = enriched.Slots.Where(s => !s.IsAvailable).ToList();
        Assert.Equal(results[0] ? 1 : 2, blocked.Count);
        Assert.All(blocked, s => Assert.Equal("ApprovedViewing", s.UnavailableReason));
        Assert.Equal(8 - blocked.Count, (await availability.GetSlotsAsync(property.Id, day)).Slots.Count);
        var createService = new ViewingService(setup);
        var conflict = await Assert.ThrowsAsync<ViewingServiceException>(() => createService.CreateAsync(Guid.NewGuid(),
            new() { PropertyId = property.Id, RequestedDateTime = blocked[0].RequestedDateTime, TenantMessage = "Visit" }));
        Assert.Equal(ViewingServiceError.Conflict, conflict.Error);
    }

    [PostgreSqlFact]
    public async Task CompetingCompletions_WaitForPropertyLock_ReloadStateAndRejectRepeat()
    {
        await using var database = new Database();
        await database.CreateAsync();
        await using var setup = new ApplicationDbContext(database.Options);
        var (property, slot) = await SeedAsync(setup);
        var tenant = new ApplicationUser
        {
            Id = Guid.NewGuid(),
            FullName = "Test tenant", Email = $"{Guid.NewGuid():N}@example.test",
            NormalizedEmail = Guid.NewGuid().ToString("N"), PhoneNumber = "0000000000",
            PasswordHash = "test-only", Role = UserRole.Tenant
        };
        var viewing = new ViewingRequest
        {
            PropertyId = property.Id, TenantId = tenant.Id, RequestedDateTime = slot.RequestedDateTime,
            DurationMinutes = 30, Status = ViewingStatus.Approved
        };
        setup.AddRange(tenant, viewing);
        await setup.SaveChangesAsync();
        var clock = new ViewingCancellationTests.Clock(viewing.RequestedDateTime.AddMinutes(30).AddTicks(-1));
        var actor = new ViewingCompletionTests.Actor(property.LandlordId, UserRole.Landlord);
        var service = new ViewingService(setup, clock, actor);
        Assert.Equal(ViewingServiceError.Conflict,
            (await Assert.ThrowsAsync<ViewingServiceException>(() => service.CompleteAsync(viewing.Id))).Error);
        clock.Now = clock.Now.AddTicks(1);
        await using var blocker = new ApplicationDbContext(database.Options);
        await using var held = await blocker.Database.BeginTransactionAsync();
        await blocker.Database.ExecuteSqlInterpolatedAsync($"SELECT 1 FROM \"Properties\" WHERE \"Id\" = {property.Id} FOR UPDATE");
        await using var db1 = new ApplicationDbContext(database.Options);
        await using var db2 = new ApplicationDbContext(database.Options);
        // Both contexts start with tracked Approved state, before waiting for the lock.
        await db1.ViewingRequests.SingleAsync();
        await db2.ViewingRequests.SingleAsync();
        async Task<bool> Complete(ApplicationDbContext context)
        {
            try
            {
                var result = await new ViewingService(context, clock, actor).CompleteAsync(viewing.Id);
                Assert.Equal(ViewingStatus.Completed, result.Status);
                Assert.Equal(clock.Now, result.UpdatedAt);
                return true;
            }
            catch (ViewingServiceException error)
            {
                Assert.Equal(ViewingServiceError.Conflict, error.Error);
                return false;
            }
        }
        var first = Complete(db1);
        var second = Complete(db2);
        await Task.Delay(200);
        Assert.False(first.IsCompleted);
        Assert.False(second.IsCompleted);
        await held.CommitAsync();
        var results = await Task.WhenAll(first, second).WaitAsync(TimeSpan.FromSeconds(20));
        Assert.Single(results, success => success);
        setup.ChangeTracker.Clear();
        var stored = await setup.ViewingRequests.SingleAsync();
        Assert.Equal(ViewingStatus.Completed, stored.Status);
        Assert.Equal(clock.Now, stored.UpdatedAt);
        Assert.Equal(viewing.RequestedDateTime, stored.RequestedDateTime);
        Assert.Equal(30, stored.DurationMinutes);
        Assert.Equal(tenant.Id, stored.TenantId);
        Assert.Equal(property.Id, stored.PropertyId);
        Assert.Empty(await setup.Notifications.ToListAsync());
    }

    [PostgreSqlFact]
    public async Task ConcurrentSameTenantSubmissions_PreserveExactDuplicateRule_WhileOtherTenantMayRequest()
    {
        await using var database = new Database(); await database.CreateAsync();
        await using var setup = new ApplicationDbContext(database.Options);
        var (property, slot) = await SeedAsync(setup);
        var tenant = Guid.NewGuid();
        var input = new CreateViewingRequestDto { TenantMessage = "Please arrange a visit.", PropertyId = property.Id, RequestedDateTime = slot.RequestedDateTime };
        await using var db1 = new ApplicationDbContext(database.Options); await using var db2 = new ApplicationDbContext(database.Options);
        async Task<bool> Create(ApplicationDbContext context)
        {
            try { await new ViewingService(context).CreateAsync(tenant, input); return true; }
            catch (ViewingServiceException error) { Assert.Equal(ViewingServiceError.Conflict, error.Error); return false; }
        }
        var results = await Task.WhenAll(Create(db1), Create(db2)).WaitAsync(TimeSpan.FromSeconds(20));
        Assert.Single(results, success => success);
        Assert.Equal(1, await setup.ViewingRequests.CountAsync());
        var other = await new ViewingService(setup).CreateAsync(Guid.NewGuid(), input);
        Assert.Equal(ViewingStatus.Pending, other.Status);
        Assert.Equal(2, await setup.ViewingRequests.CountAsync());
        Assert.Equal(2, await setup.Notifications.CountAsync(n => n.EventType == "viewing.created"));
    }
}
