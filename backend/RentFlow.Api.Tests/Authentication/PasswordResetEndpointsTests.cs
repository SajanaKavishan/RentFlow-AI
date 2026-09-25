using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using RentFlow.Api.Data;
using RentFlow.Api.Models;
using RentFlow.Api.Services;
using Xunit;

namespace RentFlow.Api.Tests.Authentication;

public sealed class PasswordResetEndpointsTests
{
    private const string OldPassword = "Original1!Password";
    private const string NewPassword = "Replacement2@Password";
    private const string GenericMessage =
        "If an account exists, password reset instructions have been created.";

    [Fact]
    public async Task ForgotPassword_ReturnsSameGenericDevelopmentShapeWithoutAccountEnumeration()
    {
        using var factory = DevelopmentFactory();
        await SeedUserAsync(factory, "tenant@example.com", UserRole.Tenant);
        await SeedUserAsync(factory, "admin@example.com", UserRole.Admin, isActive: false);
        using var client = factory.CreateHttpsClient();

        var existing = await ForgotAsync(client, " TENANT@example.com ");
        var missing = await ForgotAsync(client, "missing@example.com");
        var inactive = await ForgotAsync(client, "admin@example.com");

        foreach (var response in new[] { existing, missing, inactive })
        {
            Assert.Equal(HttpStatusCode.OK, response.StatusCode);
            var text = await response.Content.ReadAsStringAsync();
            using var body = JsonDocument.Parse(text);
            Assert.Equal(GenericMessage, body.RootElement.GetProperty("message").GetString());
            Assert.StartsWith(
                "https://web.example.test/reset-password#token=",
                body.RootElement.GetProperty("developmentResetLink").GetString());
            Assert.DoesNotContain("Tenant", text, StringComparison.OrdinalIgnoreCase);
            Assert.DoesNotContain("Admin", text, StringComparison.OrdinalIgnoreCase);
            Assert.DoesNotContain("active", text, StringComparison.OrdinalIgnoreCase);
        }

        existing.Dispose();
        missing.Dispose();
        inactive.Dispose();
    }

    [Fact]
    public async Task ForgotPassword_RejectsInvalidEmailAndIsRateLimited()
    {
        using var invalidFactory = DevelopmentFactory();
        using var invalidClient = invalidFactory.CreateHttpsClient();
        using var invalid = await ForgotAsync(invalidClient, "not-an-email");
        Assert.Equal(HttpStatusCode.BadRequest, invalid.StatusCode);

        using var limitedFactory = DevelopmentFactory();
        using var limitedClient = limitedFactory.CreateHttpsClient();
        var responses = new List<HttpResponseMessage>();
        for (var index = 0; index < 6; index++)
        {
            responses.Add(await ForgotAsync(limitedClient, $"missing-{index}@example.com"));
        }

        Assert.All(responses.Take(5), response => Assert.Equal(HttpStatusCode.OK, response.StatusCode));
        Assert.Equal(HttpStatusCode.TooManyRequests, responses[5].StatusCode);
        responses.ForEach(response => response.Dispose());
    }

    [Fact]
    public async Task ForgotPassword_StoresOnlyDigestWithShortExpiryAndNeverLogsRawToken()
    {
        var clock = new MutableTimeProvider(new DateTimeOffset(2026, 9, 26, 0, 0, 0, TimeSpan.Zero));
        using var factory = DevelopmentFactory(clock);
        var userId = await SeedUserAsync(factory, "user@example.com", UserRole.Landlord);
        using var client = factory.CreateHttpsClient();

        var rawToken = await RequestResetTokenAsync(client, "user@example.com");

        using var scope = factory.Services.CreateScope();
        var context = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
        var stored = await context.PasswordResetTokens.SingleAsync();
        Assert.Equal(userId, stored.UserId);
        Assert.Equal(clock.GetUtcNow(), stored.CreatedAt);
        Assert.Equal(clock.GetUtcNow().AddMinutes(45), stored.ExpiresAt);
        Assert.Null(stored.ConsumedAt);
        Assert.NotEqual(rawToken, stored.TokenDigest);
        Assert.Equal(
            Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(rawToken))),
            stored.TokenDigest);
        Assert.All(factory.Logs.Messages, message =>
            Assert.DoesNotContain(rawToken, message, StringComparison.Ordinal));
    }

    [Fact]
    public async Task DevelopmentResetLink_IsAbsentOutsideDevelopment()
    {
        using var factory = new AuthApiFactory(environmentName: "Production");
        await SeedUserAsync(factory, "user@example.com", UserRole.Tenant);
        using var client = factory.CreateHttpsClient();

        using var existing = await ForgotAsync(client, "user@example.com");
        using var missing = await ForgotAsync(client, "missing@example.com");
        var existingText = await existing.Content.ReadAsStringAsync();
        var missingText = await missing.Content.ReadAsStringAsync();

        Assert.Equal(HttpStatusCode.OK, existing.StatusCode);
        Assert.Equal(HttpStatusCode.OK, missing.StatusCode);
        Assert.Equal(existingText, missingText);
        Assert.DoesNotContain("developmentResetLink", existingText, StringComparison.Ordinal);
        Assert.DoesNotContain("reset-password#token", existingText, StringComparison.Ordinal);
        Assert.Equal(GenericMessage, JsonDocument.Parse(existingText).RootElement.GetProperty("message").GetString());
    }

    [Fact]
    public async Task ResetPassword_RejectsExpiredInvalidAndReusedTokens()
    {
        var clock = new MutableTimeProvider(new DateTimeOffset(2026, 9, 26, 0, 0, 0, TimeSpan.Zero));
        using var factory = DevelopmentFactory(clock);
        await SeedUserAsync(factory, "user@example.com", UserRole.Tenant);
        using var client = factory.CreateHttpsClient();
        var expiredToken = await RequestResetTokenAsync(client, "user@example.com");
        clock.Advance(TimeSpan.FromMinutes(46));

        using var expired = await ResetAsync(client, expiredToken, NewPassword, NewPassword);
        using var invalid = await ResetAsync(
            client,
            "invalid-reset-token-value-that-is-long-enough",
            NewPassword,
            NewPassword);

        AssertInvalidToken(expired);
        AssertInvalidToken(invalid);

        var validToken = await RequestResetTokenAsync(client, "user@example.com");
        using var success = await ResetAsync(client, validToken, NewPassword, NewPassword);
        using var reused = await ResetAsync(client, validToken, "Another3#Password", "Another3#Password");
        Assert.Equal(HttpStatusCode.OK, success.StatusCode);
        AssertInvalidToken(reused);

        using var scope = factory.Services.CreateScope();
        var context = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
        Assert.Equal(2, await context.PasswordResetTokens.CountAsync(token => token.ConsumedAt != null));
        Assert.Single(await context.Notifications.ToListAsync());
    }

    [Fact]
    public async Task ResetPassword_RejectsWeakOrMismatchedPasswordWithoutConsumingToken()
    {
        using var factory = DevelopmentFactory();
        var userId = await SeedUserAsync(factory, "user@example.com", UserRole.Tenant);
        using var client = factory.CreateHttpsClient();
        var token = await RequestResetTokenAsync(client, "user@example.com");

        using var weak = await ResetAsync(client, token, "alllowercase", "alllowercase");
        using var mismatch = await ResetAsync(client, token, NewPassword, "Different3#Password");

        Assert.Equal(HttpStatusCode.BadRequest, weak.StatusCode);
        Assert.Contains("uppercase", await weak.Content.ReadAsStringAsync(), StringComparison.OrdinalIgnoreCase);
        Assert.Equal(HttpStatusCode.BadRequest, mismatch.StatusCode);
        Assert.Contains("must match", await mismatch.Content.ReadAsStringAsync(), StringComparison.OrdinalIgnoreCase);

        using var scope = factory.Services.CreateScope();
        var services = scope.ServiceProvider;
        var context = services.GetRequiredService<ApplicationDbContext>();
        Assert.Null((await context.PasswordResetTokens.SingleAsync()).ConsumedAt);
        var user = await context.Users.SingleAsync(candidate => candidate.Id == userId);
        var hasher = services.GetRequiredService<IPasswordHasher<ApplicationUser>>();
        Assert.NotEqual(
            PasswordVerificationResult.Failed,
            hasher.VerifyHashedPassword(user, user.PasswordHash!, OldPassword));
        Assert.Empty(await context.Notifications.ToListAsync());
    }

    [Fact]
    public async Task SuccessfulReset_ReplacesHashInvalidatesSessionsAndCreatesOneMandatorySafeNotification()
    {
        using var factory = DevelopmentFactory();
        var userId = await SeedUserAsync(
            factory,
            "user@example.com",
            UserRole.MaintenanceTechnician,
            tokenVersion: 4);
        await DisableOptionalNotificationsAsync(factory, userId);
        using var client = factory.CreateHttpsClient();
        var oldAccessToken = await LoginAndGetTokenAsync(client, "user@example.com", OldPassword);
        var rawResetToken = await RequestResetTokenAsync(client, "user@example.com");

        using var response = await ResetAsync(client, rawResetToken, NewPassword, NewPassword);
        var responseText = await response.Content.ReadAsStringAsync();

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Contains("reset successfully", responseText, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain(rawResetToken, responseText, StringComparison.Ordinal);
        Assert.DoesNotContain(NewPassword, responseText, StringComparison.Ordinal);
        Assert.DoesNotContain("accessToken", responseText, StringComparison.OrdinalIgnoreCase);

        using (var scope = factory.Services.CreateScope())
        {
            var services = scope.ServiceProvider;
            var context = services.GetRequiredService<ApplicationDbContext>();
            var user = await context.Users.SingleAsync(candidate => candidate.Id == userId);
            var hasher = services.GetRequiredService<IPasswordHasher<ApplicationUser>>();
            Assert.Equal(5, user.TokenVersion);
            Assert.Equal(
                PasswordVerificationResult.Failed,
                hasher.VerifyHashedPassword(user, user.PasswordHash!, OldPassword));
            Assert.NotEqual(
                PasswordVerificationResult.Failed,
                hasher.VerifyHashedPassword(user, user.PasswordHash!, NewPassword));
            Assert.NotNull((await context.PasswordResetTokens.SingleAsync()).ConsumedAt);

            var notification = await context.Notifications.SingleAsync();
            Assert.Equal(userId, notification.RecipientId);
            Assert.Equal("account.password_reset", notification.EventType);
            Assert.Equal("UserAccount", notification.RelatedResourceType);
            Assert.Equal(userId, notification.RelatedResourceId);
            Assert.Equal("Password reset", notification.Title);
            Assert.Equal("Your password was reset successfully.", notification.Message);
            var notificationText = $"{notification.EventType} {notification.Title} {notification.Message}";
            Assert.DoesNotContain(rawResetToken, notificationText, StringComparison.Ordinal);
            Assert.DoesNotContain(NewPassword, notificationText, StringComparison.Ordinal);
            Assert.DoesNotContain(user.PasswordHash!, notificationText, StringComparison.Ordinal);
        }

        using var staleClient = factory.CreateHttpsClient();
        staleClient.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", oldAccessToken);
        using var staleResponse = await staleClient.GetAsync("/api/auth/me");
        Assert.Equal(HttpStatusCode.Unauthorized, staleResponse.StatusCode);

        using var oldLogin = await LoginAsync(client, "user@example.com", OldPassword);
        using var newLogin = await LoginAsync(client, "user@example.com", NewPassword);
        Assert.Equal(HttpStatusCode.Unauthorized, oldLogin.StatusCode);
        Assert.Equal(HttpStatusCode.OK, newLogin.StatusCode);
    }

    [Fact]
    public async Task ResetPassword_AttemptsAreRateLimited()
    {
        using var factory = DevelopmentFactory();
        using var client = factory.CreateHttpsClient();
        var responses = new List<HttpResponseMessage>();
        for (var index = 0; index < 6; index++)
        {
            responses.Add(await ResetAsync(
                client,
                $"invalid-reset-token-value-long-enough-{index}",
                NewPassword,
                NewPassword));
        }

        Assert.All(responses.Take(5), response => Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode));
        Assert.Equal(HttpStatusCode.TooManyRequests, responses[5].StatusCode);
        responses.ForEach(response => response.Dispose());
    }

    private static AuthApiFactory DevelopmentFactory(TimeProvider? timeProvider = null) =>
        new(timeProvider, "Development");

    private static Task<HttpResponseMessage> ForgotAsync(HttpClient client, string email) =>
        client.PostAsJsonAsync("/api/auth/forgot-password", new { email });

    private static Task<HttpResponseMessage> ResetAsync(
        HttpClient client,
        string token,
        string newPassword,
        string confirmation) =>
        client.PostAsJsonAsync("/api/auth/reset-password", new
        {
            token,
            newPassword,
            newPasswordConfirmation = confirmation
        });

    private static Task<HttpResponseMessage> LoginAsync(
        HttpClient client,
        string email,
        string password) =>
        client.PostAsJsonAsync("/api/auth/login", new { email, password });

    private static async Task<string> LoginAndGetTokenAsync(
        HttpClient client,
        string email,
        string password)
    {
        using var response = await LoginAsync(client, email, password);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        return body.RootElement.GetProperty("accessToken").GetString()!;
    }

    private static async Task<string> RequestResetTokenAsync(HttpClient client, string email)
    {
        using var response = await ForgotAsync(client, email);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        var link = new Uri(body.RootElement.GetProperty("developmentResetLink").GetString()!);
        const string prefix = "#token=";
        Assert.StartsWith(prefix, link.Fragment);
        return Uri.UnescapeDataString(link.Fragment[prefix.Length..]);
    }

    private static void AssertInvalidToken(HttpResponseMessage response)
    {
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        var text = response.Content.ReadAsStringAsync().GetAwaiter().GetResult();
        Assert.Contains("invalid, expired, or has already been used", text, StringComparison.OrdinalIgnoreCase);
    }

    private static async Task<Guid> SeedUserAsync(
        AuthApiFactory factory,
        string email,
        UserRole role,
        bool isActive = true,
        int tokenVersion = 0)
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
            IsActive = isActive,
            TokenVersion = tokenVersion,
            CreatedAt = now,
            UpdatedAt = now
        };
        var hasher = services.GetRequiredService<IPasswordHasher<ApplicationUser>>();
        user.PasswordHash = hasher.HashPassword(user, OldPassword);
        context.Users.Add(user);
        await context.SaveChangesAsync();
        return user.Id;
    }

    private static async Task DisableOptionalNotificationsAsync(
        AuthApiFactory factory,
        Guid userId)
    {
        using var scope = factory.Services.CreateScope();
        var context = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
        context.NotificationPreferences.Add(new NotificationPreference
        {
            UserId = userId,
            ViewingUpdatesEnabled = false,
            RentalApplicationUpdatesEnabled = false
        });
        await context.SaveChangesAsync();
    }

    private sealed class MutableTimeProvider(DateTimeOffset utcNow) : TimeProvider
    {
        private DateTimeOffset _utcNow = utcNow;

        public override DateTimeOffset GetUtcNow() => _utcNow;

        public void Advance(TimeSpan duration) => _utcNow = _utcNow.Add(duration);
    }
}
