using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.IdentityModel.Tokens.Jwt;
using System.Text.Json;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using RentFlow.Api.Data;
using RentFlow.Api.Models;
using Xunit;

namespace RentFlow.Api.Tests.Authentication;

public sealed class ChangePasswordEndpointsTests
{
    private const string CurrentPassword = "Secure1!Password";
    private const string NewPassword = "NewSecure2@Password";

    [Fact]
    public async Task ChangePassword_RequiresAuthentication()
    {
        using var factory = new AuthApiFactory();
        using var client = factory.CreateHttpsClient();

        var response = await ChangePasswordAsync(
            client,
            CurrentPassword,
            NewPassword,
            NewPassword);

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task ChangePassword_RejectsAnAccountThatBecameInactive()
    {
        using var factory = new AuthApiFactory();
        using var client = factory.CreateHttpsClient();
        var registration = await RegisterAsync(client, "inactive-change@example.com");
        var body = await ParseAsync(registration);
        var userId = body.RootElement.GetProperty("user").GetProperty("id").GetGuid();
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue(
            "Bearer",
            body.RootElement.GetProperty("accessToken").GetString());

        using (var scope = factory.Services.CreateScope())
        {
            var context = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
            var user = await context.Users.SingleAsync(candidate => candidate.Id == userId);
            user.IsActive = false;
            await context.SaveChangesAsync();
        }

        var response = await ChangePasswordAsync(
            client,
            CurrentPassword,
            NewPassword,
            NewPassword);

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
        using var verificationScope = factory.Services.CreateScope();
        var services = verificationScope.ServiceProvider;
        var stored = await services.GetRequiredService<ApplicationDbContext>()
            .Users.SingleAsync(candidate => candidate.Id == userId);
        var hasher = services.GetRequiredService<IPasswordHasher<ApplicationUser>>();
        Assert.NotEqual(
            PasswordVerificationResult.Failed,
            hasher.VerifyHashedPassword(stored, stored.PasswordHash!, CurrentPassword));
    }

    public static TheoryData<string, string, string, string> InvalidChanges => new()
    {
        { "Wrong1!Password", NewPassword, NewPassword, "Current password is incorrect." },
        { CurrentPassword, "weak", "weak", "at least 8 characters" },
        { CurrentPassword, NewPassword, "Different2@Password", "must match" },
        { CurrentPassword, CurrentPassword, CurrentPassword, "must be different" }
    };

    [Theory]
    [MemberData(nameof(InvalidChanges))]
    public async Task ChangePassword_RejectsIncorrectCurrentWeakMismatchedAndSamePasswords(
        string currentPassword,
        string newPassword,
        string confirmation,
        string expectedMessage)
    {
        using var factory = new AuthApiFactory();
        using var client = factory.CreateHttpsClient();
        var registration = await RegisterAsync(client, "invalid-change@example.com");
        var body = await ParseAsync(registration);
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue(
            "Bearer",
            body.RootElement.GetProperty("accessToken").GetString());

        var response = await ChangePasswordAsync(
            client,
            currentPassword,
            newPassword,
            confirmation);

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.Contains(
            expectedMessage,
            await response.Content.ReadAsStringAsync(),
            StringComparison.OrdinalIgnoreCase);
        Assert.Equal(
            HttpStatusCode.OK,
            (await LoginAsync(client, "invalid-change@example.com", CurrentPassword)).StatusCode);
        using var verificationScope = factory.Services.CreateScope();
        var context = verificationScope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
        Assert.Equal(0, (await context.Users.SingleAsync()).TokenVersion);
        Assert.Empty(await context.Notifications.ToListAsync());
    }

    [Fact]
    public async Task ChangePassword_RotatesTokenAndInvalidatesEveryPreviouslyIssuedSession()
    {
        using var factory = new AuthApiFactory();
        using var client = factory.CreateHttpsClient();
        var registrationA = await RegisterAsync(client, "change-a@example.com");
        var bodyA = await ParseAsync(registrationA);
        var userAId = bodyA.RootElement.GetProperty("user").GetProperty("id").GetGuid();
        var existingToken = bodyA.RootElement.GetProperty("accessToken").GetString()!;
        var secondSessionLogin = await LoginAsync(client, "change-a@example.com", CurrentPassword);
        var secondSessionToken = (await ParseAsync(secondSessionLogin))
            .RootElement.GetProperty("accessToken").GetString()!;
        var registrationB = await RegisterAsync(client, "change-b@example.com");
        var bodyB = await ParseAsync(registrationB);
        var userBId = bodyB.RootElement.GetProperty("user").GetProperty("id").GetGuid();
        string originalAHash;
        string originalBHash;

        using (var scope = factory.Services.CreateScope())
        {
            var context = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
            originalAHash = (await context.Users.SingleAsync(user => user.Id == userAId)).PasswordHash!;
            originalBHash = (await context.Users.SingleAsync(user => user.Id == userBId)).PasswordHash!;
            context.NotificationPreferences.Add(new NotificationPreference
            {
                UserId = userAId,
                ViewingUpdatesEnabled = false,
                RentalApplicationUpdatesEnabled = false
            });
            await context.SaveChangesAsync();
        }

        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue(
            "Bearer",
            existingToken);
        Assert.Equal(HttpStatusCode.OK, (await client.GetAsync("/api/auth/me")).StatusCode);
        using var secondSessionClient = factory.CreateHttpsClient();
        secondSessionClient.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue(
            "Bearer",
            secondSessionToken);
        Assert.Equal(
            HttpStatusCode.OK,
            (await secondSessionClient.GetAsync("/api/auth/me")).StatusCode);

        var response = await client.PutAsJsonAsync("/api/auth/change-password", new
        {
            currentPassword = CurrentPassword,
            newPassword = NewPassword,
            newPasswordConfirmation = NewPassword,
            userId = userBId,
            email = "change-b@example.com",
            role = "Admin"
        });
        var responseText = await response.Content.ReadAsStringAsync();

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var responseBody = JsonDocument.Parse(responseText);
        var replacementToken = responseBody.RootElement.GetProperty("accessToken").GetString()!;

        Assert.Equal(
            "Your password was changed successfully.",
            responseBody.RootElement.GetProperty("message").GetString());
        Assert.True(responseBody.RootElement.GetProperty("expiresAt").GetDateTimeOffset()
            > DateTimeOffset.UtcNow);
        var parsedReplacementToken = new JwtSecurityTokenHandler().ReadJwtToken(replacementToken);
        Assert.Equal(
            "1",
            parsedReplacementToken.Claims.Single(claim => claim.Type == "token_version").Value);

        using (var scope = factory.Services.CreateScope())
        {
            var services = scope.ServiceProvider;
            var context = services.GetRequiredService<ApplicationDbContext>();
            var userA = await context.Users.SingleAsync(user => user.Id == userAId);
            var userB = await context.Users.SingleAsync(user => user.Id == userBId);
            var hasher = services.GetRequiredService<IPasswordHasher<ApplicationUser>>();

            Assert.NotEqual(originalAHash, userA.PasswordHash);
            Assert.Equal(1, userA.TokenVersion);
            Assert.Equal(
                PasswordVerificationResult.Failed,
                hasher.VerifyHashedPassword(userA, userA.PasswordHash!, CurrentPassword));
            Assert.NotEqual(
                PasswordVerificationResult.Failed,
                hasher.VerifyHashedPassword(userA, userA.PasswordHash!, NewPassword));
            Assert.Equal(originalBHash, userB.PasswordHash);
            Assert.NotEqual(
                PasswordVerificationResult.Failed,
                hasher.VerifyHashedPassword(userB, userB.PasswordHash!, CurrentPassword));

            var notification = await context.Notifications.SingleAsync();
            Assert.Equal(userAId, notification.RecipientId);
            Assert.Equal("account.password_changed", notification.EventType);
            Assert.Equal("UserAccount", notification.RelatedResourceType);
            Assert.Equal(userAId, notification.RelatedResourceId);
            Assert.Equal("Password changed", notification.Title);
            Assert.Equal("Your password was changed successfully.", notification.Message);
            Assert.Null(notification.ReadAt);
        }

        Assert.Equal(HttpStatusCode.Unauthorized, (await client.GetAsync("/api/auth/me")).StatusCode);
        Assert.Equal(
            HttpStatusCode.Unauthorized,
            (await secondSessionClient.GetAsync("/api/auth/me")).StatusCode);
        using var replacementClient = factory.CreateHttpsClient();
        replacementClient.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue(
            "Bearer",
            replacementToken);
        Assert.Equal(
            HttpStatusCode.OK,
            (await replacementClient.GetAsync("/api/auth/me")).StatusCode);

        using var loginClient = factory.CreateHttpsClient();
        Assert.Equal(
            HttpStatusCode.Unauthorized,
            (await LoginAsync(loginClient, "change-a@example.com", CurrentPassword)).StatusCode);
        Assert.Equal(
            HttpStatusCode.OK,
            (await LoginAsync(loginClient, "change-a@example.com", NewPassword)).StatusCode);

        var sensitiveValues = new[]
        {
            CurrentPassword,
            NewPassword,
            existingToken,
            secondSessionToken,
            originalAHash,
            originalBHash
        };
        foreach (var sensitiveValue in sensitiveValues)
        {
            Assert.DoesNotContain(sensitiveValue, responseText, StringComparison.Ordinal);
            Assert.DoesNotContain(
                factory.Logs.Messages,
                message => message.Contains(sensitiveValue, StringComparison.Ordinal));
        }
        Assert.DoesNotContain(
            factory.Logs.Messages,
            message => message.Contains(replacementToken, StringComparison.Ordinal));
    }

    private static Task<HttpResponseMessage> RegisterAsync(HttpClient client, string email) =>
        client.PostAsJsonAsync("/api/auth/register", new
        {
            fullName = "Change Password User",
            email,
            phoneNumber = "+94770000000",
            password = CurrentPassword,
            role = "Tenant"
        });

    private static Task<HttpResponseMessage> LoginAsync(
        HttpClient client,
        string email,
        string password) =>
        client.PostAsJsonAsync("/api/auth/login", new { email, password });

    private static Task<HttpResponseMessage> ChangePasswordAsync(
        HttpClient client,
        string currentPassword,
        string newPassword,
        string confirmation) =>
        client.PutAsJsonAsync("/api/auth/change-password", new
        {
            currentPassword,
            newPassword,
            newPasswordConfirmation = confirmation
        });

    private static async Task<JsonDocument> ParseAsync(HttpResponseMessage response) =>
        JsonDocument.Parse(await response.Content.ReadAsStringAsync());
}
