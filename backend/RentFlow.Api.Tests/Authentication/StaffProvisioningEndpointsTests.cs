using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using RentFlow.Api.Data;
using RentFlow.Api.DTOs.Notifications;
using RentFlow.Api.Models;
using RentFlow.Api.Services;
using Xunit;

namespace RentFlow.Api.Tests.Authentication;

public sealed class StaffProvisioningEndpointsTests
{
    private const string AdminPassword = "Admin1!Password";
    private const string TechnicianPassword = "Tech1!Password";

    [Fact]
    public async Task Create_RequiresAdminAuthenticationAndDatabaseRole()
    {
        using var factory = new AuthApiFactory();
        using var anonymous = factory.CreateHttpsClient();

        var anonymousResponse = await CreateTechnicianAsync(anonymous);

        Assert.Equal(HttpStatusCode.Unauthorized, anonymousResponse.StatusCode);

        var tenant = await SeedUserAndLoginAsync(
            factory,
            "tenant@example.com",
            UserRole.Tenant);
        using var tenantClient = AuthorizedClient(factory, tenant.Token);

        var tenantResponse = await CreateTechnicianAsync(
            tenantClient,
            "second@example.com");

        Assert.Equal(HttpStatusCode.Forbidden, tenantResponse.StatusCode);
    }

    [Theory]
    [InlineData(false, "Admin")]
    [InlineData(true, "Landlord")]
    public async Task Create_RejectsStaleAdminJwtAfterDatabaseChange(
        bool isActive,
        string databaseRole)
    {
        using var factory = new AuthApiFactory();
        var admin = await SeedUserAndLoginAsync(
            factory,
            "admin@example.com",
            UserRole.Admin);
        await UpdateUserAsync(
            factory,
            admin.UserId,
            isActive,
            Enum.Parse<UserRole>(databaseRole));
        using var client = AuthorizedClient(factory, admin.Token);

        var response = await CreateTechnicianAsync(client);

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Fact]
    public async Task Create_AssignsInactiveTechnicianRoleAndStoresOnlyTokenDigest()
    {
        using var factory = new AuthApiFactory();
        var admin = await SeedUserAndLoginAsync(
            factory,
            "admin@example.com",
            UserRole.Admin);
        using var client = AuthorizedClient(factory, admin.Token);

        var response = await client.PostAsJsonAsync(
            "/api/admin/maintenance-technicians",
            new
            {
                fullName = "Pending Technician",
                email = "technician@example.com",
                phoneNumber = "+94770000001",
                role = "Admin"
            });
        var responseText = await response.Content.ReadAsStringAsync();
        using var body = JsonDocument.Parse(responseText);
        var setupToken = body.RootElement.GetProperty("passwordSetupToken").GetString()!;

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        Assert.Equal(
            "MaintenanceTechnician",
            body.RootElement.GetProperty("role").GetString());
        Assert.False(body.RootElement.GetProperty("isActive").GetBoolean());
        Assert.DoesNotContain("passwordHash", responseText, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("accessToken", responseText, StringComparison.OrdinalIgnoreCase);

        using var scope = factory.Services.CreateScope();
        var context = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
        var technician = await context.Users.SingleAsync(
            user => user.NormalizedEmail == "TECHNICIAN@EXAMPLE.COM");
        var storedToken = await context.TechnicianPasswordSetupTokens.SingleAsync();
        Assert.Equal(UserRole.MaintenanceTechnician, technician.Role);
        Assert.False(technician.IsActive);
        Assert.Null(technician.PasswordHash);
        Assert.Equal(admin.UserId, storedToken.CreatedByAdminId);
        Assert.NotEqual(setupToken, storedToken.TokenDigest);
        Assert.DoesNotContain(setupToken, storedToken.TokenDigest, StringComparison.Ordinal);
    }

    [Fact]
    public async Task PendingTechnician_CannotLoginUntilSingleUseActivationCompletes()
    {
        using var factory = new AuthApiFactory();
        var setupToken = await CreatePendingTechnicianAsync(factory);
        using var client = factory.CreateHttpsClient();

        var pendingLogin = await LoginAsync(
            client,
            "technician@example.com",
            TechnicianPassword);
        var activation = await ActivateAsync(client, setupToken, TechnicianPassword);
        var reused = await ActivateAsync(client, setupToken, "Different2!Password");
        var activeLogin = await LoginAsync(
            client,
            "technician@example.com",
            TechnicianPassword);

        Assert.Equal(HttpStatusCode.Unauthorized, pendingLogin.StatusCode);
        Assert.Equal(HttpStatusCode.NoContent, activation.StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, reused.StatusCode);
        Assert.Equal(HttpStatusCode.OK, activeLogin.StatusCode);

        using var scope = factory.Services.CreateScope();
        var services = scope.ServiceProvider;
        var context = services.GetRequiredService<ApplicationDbContext>();
        var technician = await context.Users.SingleAsync(
            user => user.NormalizedEmail == "TECHNICIAN@EXAMPLE.COM");
        var token = await context.TechnicianPasswordSetupTokens.SingleAsync();
        Assert.True(technician.IsActive);
        Assert.NotNull(token.ConsumedAt);
        Assert.NotEqual(TechnicianPassword, technician.PasswordHash);
        var hasher = services.GetRequiredService<IPasswordHasher<ApplicationUser>>();
        Assert.NotEqual(
            PasswordVerificationResult.Failed,
            hasher.VerifyHashedPassword(
                technician,
                technician.PasswordHash!,
                TechnicianPassword));
        Assert.Single(await context.Notifications.ToListAsync());
    }

    [Fact]
    public async Task Activation_NotifiesOnlyProvisioningAdminWithoutAuthenticationSecrets()
    {
        using var factory = new AuthApiFactory();
        var provisioningAdmin = await SeedUserAndLoginAsync(
            factory,
            "provisioning-admin@example.com",
            UserRole.Admin);
        var otherAdmin = await SeedUserAndLoginAsync(
            factory,
            "other-admin@example.com",
            UserRole.Admin);
        using var provisioningAdminClient = AuthorizedClient(
            factory,
            provisioningAdmin.Token);
        var preferenceResponse = await provisioningAdminClient.PutAsJsonAsync(
            "/api/notification-preferences",
            new
            {
                viewingUpdatesEnabled = false,
                rentalApplicationUpdatesEnabled = false,
                accountSecurityUpdatesEnabled = true
            });
        Assert.Equal(HttpStatusCode.OK, preferenceResponse.StatusCode);
        using var createResponse = await CreateTechnicianAsync(provisioningAdminClient);
        Assert.Equal(HttpStatusCode.Created, createResponse.StatusCode);
        using var createBody = JsonDocument.Parse(
            await createResponse.Content.ReadAsStringAsync());
        var setupToken = createBody.RootElement
            .GetProperty("passwordSetupToken")
            .GetString()!;
        var technicianId = createBody.RootElement.GetProperty("id").GetGuid();
        using var anonymous = factory.CreateHttpsClient();

        var activation = await ActivateAsync(
            anonymous,
            setupToken,
            TechnicianPassword);

        Assert.Equal(HttpStatusCode.NoContent, activation.StatusCode);
        using var scope = factory.Services.CreateScope();
        var context = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
        var notification = await context.Notifications.SingleAsync();
        var technician = await context.Users.SingleAsync(
            user => user.Id == technicianId);
        Assert.Equal(provisioningAdmin.UserId, notification.RecipientId);
        Assert.NotEqual(otherAdmin.UserId, notification.RecipientId);
        Assert.Equal("maintenance_technician.activated", notification.EventType);
        Assert.Equal("MaintenanceTechnician", notification.RelatedResourceType);
        Assert.Equal(technicianId, notification.RelatedResourceId);
        Assert.Equal("Technician account activated", notification.Title);
        Assert.Equal(
            "The Maintenance Technician account you provisioned is now active.",
            notification.Message);
        Assert.Null(notification.ReadAt);

        var notificationText = string.Join(
            ' ',
            notification.EventType,
            notification.RelatedResourceType,
            notification.Title,
            notification.Message);
        Assert.DoesNotContain(setupToken, notificationText, StringComparison.Ordinal);
        Assert.DoesNotContain(TechnicianPassword, notificationText, StringComparison.Ordinal);
        Assert.DoesNotContain(technician.PasswordHash!, notificationText, StringComparison.Ordinal);
        Assert.DoesNotContain("http", notificationText, StringComparison.OrdinalIgnoreCase);

        var provisioningAdminPage = await provisioningAdminClient
            .GetFromJsonAsync<NotificationPageResponseDto>("/api/notifications");
        Assert.NotNull(provisioningAdminPage);
        var delivered = Assert.Single(provisioningAdminPage!.Items);
        Assert.Equal(notification.Id, delivered.Id);
        Assert.Equal("maintenance_technician.activated", delivered.EventType);

        using var otherAdminClient = AuthorizedClient(factory, otherAdmin.Token);
        var otherAdminPage = await otherAdminClient
            .GetFromJsonAsync<NotificationPageResponseDto>("/api/notifications");
        Assert.NotNull(otherAdminPage);
        Assert.Empty(otherAdminPage!.Items);
    }

    [Fact]
    public async Task Activation_RejectsWeakPasswordWithoutConsumingToken()
    {
        using var factory = new AuthApiFactory();
        var setupToken = await CreatePendingTechnicianAsync(factory);
        using var client = factory.CreateHttpsClient();

        var response = await ActivateAsync(client, setupToken, "alllowercase");

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        using var scope = factory.Services.CreateScope();
        var context = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
        Assert.Null((await context.TechnicianPasswordSetupTokens.SingleAsync()).ConsumedAt);
        Assert.False((await context.Users.SingleAsync(
            user => user.Role == UserRole.MaintenanceTechnician)).IsActive);
        Assert.Empty(await context.Notifications.ToListAsync());
    }

    [Fact]
    public async Task Activation_RejectsExpiredToken()
    {
        var clock = new MutableTimeProvider(TimeProvider.System.GetUtcNow());
        using var factory = new AuthApiFactory(clock);
        var setupToken = await CreatePendingTechnicianAsync(factory);
        clock.Advance(TimeSpan.FromMinutes(61));
        using var client = factory.CreateHttpsClient();

        var response = await ActivateAsync(client, setupToken, TechnicianPassword);

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        using var scope = factory.Services.CreateScope();
        var context = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
        Assert.Null((await context.TechnicianPasswordSetupTokens.SingleAsync()).ConsumedAt);
        Assert.False((await context.Users.SingleAsync(
            user => user.Role == UserRole.MaintenanceTechnician)).IsActive);
        Assert.Empty(await context.Notifications.ToListAsync());
    }

    [Fact]
    public async Task Create_RejectsDuplicateNormalizedEmailAndInvalidInput()
    {
        using var factory = new AuthApiFactory();
        var admin = await SeedUserAndLoginAsync(
            factory,
            "admin@example.com",
            UserRole.Admin);
        await SeedUserAsync(factory, "existing@example.com", UserRole.Tenant);
        using var client = AuthorizedClient(factory, admin.Token);

        var duplicate = await CreateTechnicianAsync(
            client,
            " EXISTING@example.com ");
        var invalid = await client.PostAsJsonAsync(
            "/api/admin/maintenance-technicians",
            new { fullName = "", email = "invalid", phoneNumber = "1" });

        Assert.Equal(HttpStatusCode.Conflict, duplicate.StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, invalid.StatusCode);
    }

    [Fact]
    public async Task ConcurrentActivationAttempts_AllowExactlyOneUse()
    {
        using var factory = new AuthApiFactory();
        var setupToken = await CreatePendingTechnicianAsync(factory);
        using var firstClient = factory.CreateHttpsClient();
        using var secondClient = factory.CreateHttpsClient();

        var responses = await Task.WhenAll(
            ActivateAsync(firstClient, setupToken, TechnicianPassword),
            ActivateAsync(secondClient, setupToken, TechnicianPassword));

        Assert.Single(
            responses,
            response => response.StatusCode == HttpStatusCode.NoContent);
        Assert.Single(
            responses,
            response => response.StatusCode == HttpStatusCode.BadRequest);

        using var scope = factory.Services.CreateScope();
        var context = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
        var notification = await context.Notifications.SingleAsync();
        Assert.Equal("maintenance_technician.activated", notification.EventType);
    }

    [Fact]
    public async Task Activation_IsRateLimited()
    {
        using var factory = new AuthApiFactory();
        using var client = factory.CreateHttpsClient();
        var responses = new List<HttpResponseMessage>();

        for (var index = 0; index < 6; index++)
        {
            responses.Add(await ActivateAsync(
                client,
                $"invalid-token-value-that-is-long-enough-{index}",
                TechnicianPassword));
        }

        Assert.All(
            responses.Take(5),
            response => Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode));
        Assert.Equal(HttpStatusCode.TooManyRequests, responses[5].StatusCode);
        responses.ForEach(response => response.Dispose());
    }

    private static async Task<string> CreatePendingTechnicianAsync(AuthApiFactory factory)
    {
        var admin = await SeedUserAndLoginAsync(
            factory,
            "admin@example.com",
            UserRole.Admin);
        using var client = AuthorizedClient(factory, admin.Token);
        using var response = await CreateTechnicianAsync(client);
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        return body.RootElement.GetProperty("passwordSetupToken").GetString()!;
    }

    private static Task<HttpResponseMessage> CreateTechnicianAsync(
        HttpClient client,
        string email = "technician@example.com") =>
        client.PostAsJsonAsync(
            "/api/admin/maintenance-technicians",
            new
            {
                fullName = "Pending Technician",
                email,
                phoneNumber = "+94770000001"
            });

    private static Task<HttpResponseMessage> ActivateAsync(
        HttpClient client,
        string setupToken,
        string password) =>
        client.PostAsJsonAsync(
            "/api/auth/maintenance-technicians/activate",
            new
            {
                setupToken,
                password,
                passwordConfirmation = password
            });

    private static Task<HttpResponseMessage> LoginAsync(
        HttpClient client,
        string email,
        string password) =>
        client.PostAsJsonAsync("/api/auth/login", new { email, password });

    private static HttpClient AuthorizedClient(AuthApiFactory factory, string token)
    {
        var client = factory.CreateHttpsClient();
        client.DefaultRequestHeaders.Authorization =
            new AuthenticationHeaderValue("Bearer", token);
        return client;
    }

    private static async Task<(Guid UserId, string Token)> SeedUserAndLoginAsync(
        AuthApiFactory factory,
        string email,
        UserRole role)
    {
        var userId = await SeedUserAsync(factory, email, role);
        using var client = factory.CreateHttpsClient();
        using var response = await LoginAsync(client, email, AdminPassword);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        return (userId, body.RootElement.GetProperty("accessToken").GetString()!);
    }

    private static async Task<Guid> SeedUserAsync(
        AuthApiFactory factory,
        string email,
        UserRole role)
    {
        using var scope = factory.Services.CreateScope();
        var services = scope.ServiceProvider;
        var context = services.GetRequiredService<ApplicationDbContext>();
        var now = services.GetRequiredService<TimeProvider>().GetUtcNow();
        var user = new ApplicationUser
        {
            Id = Guid.NewGuid(),
            FullName = $"Test {role}",
            Email = email,
            NormalizedEmail = AuthService.NormalizeEmail(email),
            PhoneNumber = "+94770000000",
            Role = role,
            IsActive = true,
            CreatedAt = now,
            UpdatedAt = now
        };
        var hasher = services.GetRequiredService<IPasswordHasher<ApplicationUser>>();
        user.PasswordHash = hasher.HashPassword(user, AdminPassword);
        context.Users.Add(user);
        await context.SaveChangesAsync();
        return user.Id;
    }

    private static async Task UpdateUserAsync(
        AuthApiFactory factory,
        Guid userId,
        bool isActive,
        UserRole role)
    {
        using var scope = factory.Services.CreateScope();
        var context = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
        var user = await context.Users.SingleAsync(candidate => candidate.Id == userId);
        user.IsActive = isActive;
        user.Role = role;
        await context.SaveChangesAsync();
    }

    private sealed class MutableTimeProvider(DateTimeOffset utcNow) : TimeProvider
    {
        private DateTimeOffset _utcNow = utcNow;

        public override DateTimeOffset GetUtcNow() => _utcNow;

        public void Advance(TimeSpan duration) => _utcNow = _utcNow.Add(duration);
    }
}
