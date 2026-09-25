using System.IdentityModel.Tokens.Jwt;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Claims;
using System.Text;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.IdentityModel.Tokens;
using RentFlow.Api.Data;
using RentFlow.Api.DTOs.Notifications;
using RentFlow.Api.Models;
using Xunit;

namespace RentFlow.Api.Tests.Authentication;

public sealed class NotificationPreferencesTests
{
    private static readonly Guid UserA = Guid.Parse("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");
    private static readonly Guid UserB = Guid.Parse("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb");

    [Fact]
    public async Task Endpoints_RequireAuthentication()
    {
        using var factory = new AuthApiFactory();
        using var client = factory.CreateHttpsClient();

        var get = await client.GetAsync("/api/notification-preferences");
        var put = await client.PutAsJsonAsync("/api/notification-preferences", new
        {
            viewingUpdatesEnabled = true,
            rentalApplicationUpdatesEnabled = true,
            accountSecurityUpdatesEnabled = true
        });

        Assert.Equal(HttpStatusCode.Unauthorized, get.StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, put.StatusCode);
    }

    [Theory]
    [InlineData(UserRole.Tenant)]
    [InlineData(UserRole.Landlord)]
    [InlineData(UserRole.MaintenanceTechnician)]
    [InlineData(UserRole.Admin)]
    public async Task DefaultsAndUpdates_AreAvailableForEveryAuthenticatedRole(UserRole role)
    {
        using var factory = new AuthApiFactory();
        await SeedUserAsync(factory, UserA, role);
        using var client = AuthorizedClient(factory, UserA, role);

        var defaults = await client.GetFromJsonAsync<NotificationPreferencesResponseDto>(
            "/api/notification-preferences");
        var updateResponse = await client.PutAsJsonAsync("/api/notification-preferences", new
        {
            viewingUpdatesEnabled = false,
            rentalApplicationUpdatesEnabled = true,
            accountSecurityUpdatesEnabled = true
        });
        var updated = await updateResponse.Content
            .ReadFromJsonAsync<NotificationPreferencesResponseDto>();

        Assert.NotNull(defaults);
        Assert.True(defaults!.ViewingUpdatesEnabled);
        Assert.True(defaults.RentalApplicationUpdatesEnabled);
        Assert.True(defaults.AccountSecurityUpdatesEnabled);
        Assert.Equal(HttpStatusCode.OK, updateResponse.StatusCode);
        Assert.NotNull(updated);
        Assert.False(updated!.ViewingUpdatesEnabled);
        Assert.True(updated.RentalApplicationUpdatesEnabled);
        Assert.True(updated.AccountSecurityUpdatesEnabled);
    }

    [Fact]
    public async Task Update_UsesJwtUserAndCannotChangeAnotherUsersPreferences()
    {
        using var factory = new AuthApiFactory();
        await SeedUserAsync(factory, UserA, UserRole.Tenant);
        await SeedUserAsync(factory, UserB, UserRole.Landlord);
        using var clientA = AuthorizedClient(factory, UserA, UserRole.Tenant);
        using var clientB = AuthorizedClient(factory, UserB, UserRole.Landlord);

        var response = await clientA.PutAsJsonAsync("/api/notification-preferences", new
        {
            userId = UserB,
            viewingUpdatesEnabled = false,
            rentalApplicationUpdatesEnabled = false,
            accountSecurityUpdatesEnabled = true
        });
        var userBPreferences = await clientB
            .GetFromJsonAsync<NotificationPreferencesResponseDto>(
                "/api/notification-preferences");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.NotNull(userBPreferences);
        Assert.True(userBPreferences!.ViewingUpdatesEnabled);
        Assert.True(userBPreferences.RentalApplicationUpdatesEnabled);

        using var scope = factory.Services.CreateScope();
        var context = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
        var stored = await context.NotificationPreferences.SingleAsync();
        Assert.Equal(UserA, stored.UserId);
        Assert.False(stored.ViewingUpdatesEnabled);
        Assert.False(stored.RentalApplicationUpdatesEnabled);
    }

    [Fact]
    public async Task Update_CannotDisableAccountSecurityNotifications()
    {
        using var factory = new AuthApiFactory();
        await SeedUserAsync(factory, UserA, UserRole.Admin);
        using var client = AuthorizedClient(factory, UserA, UserRole.Admin);

        var response = await client.PutAsJsonAsync("/api/notification-preferences", new
        {
            viewingUpdatesEnabled = false,
            rentalApplicationUpdatesEnabled = false,
            accountSecurityUpdatesEnabled = false
        });

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.Contains(
            "cannot be disabled",
            await response.Content.ReadAsStringAsync(),
            StringComparison.OrdinalIgnoreCase);
        using var scope = factory.Services.CreateScope();
        var context = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
        Assert.Empty(await context.NotificationPreferences.ToListAsync());
    }

    private static async Task SeedUserAsync(
        AuthApiFactory factory,
        Guid userId,
        UserRole role)
    {
        using var scope = factory.Services.CreateScope();
        var context = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
        context.Users.Add(new ApplicationUser
        {
            Id = userId,
            FullName = $"Preference {role}",
            Email = $"{userId:N}@example.test",
            NormalizedEmail = $"{userId:N}@EXAMPLE.TEST",
            PhoneNumber = "+94770000000",
            Role = role,
            IsActive = true,
            CreatedAt = DateTimeOffset.UtcNow,
            UpdatedAt = DateTimeOffset.UtcNow
        });
        await context.SaveChangesAsync();
    }

    private static HttpClient AuthorizedClient(
        AuthApiFactory factory,
        Guid userId,
        UserRole role)
    {
        var client = factory.CreateHttpsClient();
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue(
            "Bearer", CreateToken(userId, role));
        return client;
    }

    private static string CreateToken(Guid userId, UserRole role)
    {
        var credentials = new SigningCredentials(
            new SymmetricSecurityKey(Encoding.UTF8.GetBytes(
                "test-only-signing-key-that-is-at-least-32-bytes-long")),
            SecurityAlgorithms.HmacSha256);
        var token = new JwtSecurityToken(
            issuer: "RentFlow.Api.Tests",
            audience: "RentFlow.TestClients",
            claims:
            [
                new Claim(JwtRegisteredClaimNames.Sub, userId.ToString()),
                new Claim("role", role.ToString())
            ],
            expires: DateTime.UtcNow.AddMinutes(10),
            signingCredentials: credentials);
        return new JwtSecurityTokenHandler().WriteToken(token);
    }
}
