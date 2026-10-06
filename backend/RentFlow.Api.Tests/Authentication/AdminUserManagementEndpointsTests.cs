using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using RentFlow.Api.Data;
using RentFlow.Api.DTOs.Auth;
using RentFlow.Api.Models;
using Xunit;

namespace RentFlow.Api.Tests.Authentication;

public sealed class AdminUserManagementEndpointsTests
{
    private const string Password = "Admin1!Password";
    [Theory]
    [InlineData(UserRole.Tenant)] [InlineData(UserRole.Landlord)] [InlineData(UserRole.MaintenanceTechnician)]
    public async Task OnlyActiveAdminCanViewAndDeactivate(UserRole role)
    {
        using var factory = new AuthApiFactory(); using var anonymous = factory.CreateHttpsClient();
        var id = Guid.NewGuid(); var path = $"/api/admin/users/{id}";
        Assert.Equal(HttpStatusCode.Unauthorized, (await anonymous.GetAsync(path)).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await anonymous.PatchAsync($"{path}/deactivate", null)).StatusCode);
        var denied = await Account(factory, role); using var client = Authorized(factory, denied.Token);
        Assert.Equal(HttpStatusCode.Forbidden, (await client.GetAsync(path)).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await client.PatchAsync($"{path}/deactivate", null)).StatusCode);
    }

    [Fact]
    public async Task DeactivationBlocksLoginAndExistingJwtAndRevokesRecoveryTokens()
    {
        using var factory = new AuthApiFactory(); var actor = await Account(factory, UserRole.Admin); var target = await Account(factory, UserRole.Tenant);
        using var admin = Authorized(factory, actor.Token); using var session = Authorized(factory, target.Token);
        Assert.Equal(HttpStatusCode.OK, (await session.GetAsync("/api/auth/me")).StatusCode);
        using (var scope = factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
            db.PasswordResetTokens.Add(new PasswordResetToken { Id = Guid.NewGuid(), UserId = target.Id, TokenDigest = "reset-token", CreatedAt = DateTimeOffset.UtcNow, ExpiresAt = DateTimeOffset.UtcNow.AddHours(1) });
            db.TechnicianPasswordSetupTokens.Add(new TechnicianPasswordSetupToken { Id = Guid.NewGuid(), UserId = target.Id, CreatedByAdminId = actor.Id, TokenDigest = "setup-token", CreatedAt = DateTimeOffset.UtcNow, ExpiresAt = DateTimeOffset.UtcNow.AddHours(1) });
            await db.SaveChangesAsync();
        }
        var path = $"/api/admin/users/{target.Id}";
        using var detail = await admin.GetAsync(path); Assert.Equal(HttpStatusCode.OK, detail.StatusCode);
        using var json = JsonDocument.Parse(await detail.Content.ReadAsStringAsync());
        Assert.Equal(new[] { "id", "fullName", "email", "phoneNumber", "role", "isActive", "createdAt" }, json.RootElement.EnumerateObject().Select(property => property.Name));
        var response = await admin.PatchAsync($"{path}/deactivate", null); Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.False((await response.Content.ReadFromJsonAsync<AdminUserDetailsDto>())!.IsActive);
        Assert.Equal(HttpStatusCode.Unauthorized, (await session.GetAsync("/api/auth/me")).StatusCode);
        using var login = factory.CreateHttpsClient();
        Assert.Equal(HttpStatusCode.Unauthorized, (await login.PostAsJsonAsync("/api/auth/login", new { email = target.Email, password = Password })).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await admin.PatchAsync($"{path}/deactivate", null)).StatusCode);
        using (var scope = factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>(); var stored = (await db.Users.FindAsync(target.Id))!;
            Assert.False(stored.IsActive); Assert.Equal(1, stored.TokenVersion);
            Assert.NotNull((await db.PasswordResetTokens.SingleAsync()).ConsumedAt);
            Assert.NotNull((await db.TechnicianPasswordSetupTokens.SingleAsync()).ConsumedAt);
            stored.IsActive = true; await db.SaveChangesAsync();
        }
        Assert.Equal(HttpStatusCode.Unauthorized, (await session.GetAsync("/api/auth/me")).StatusCode);
    }

    [Fact]
    public async Task ProtectsOwnAccountAndRejectsMissingOrStaleAdmin()
    {
        using var factory = new AuthApiFactory(); var actor = await Account(factory, UserRole.Admin); using var admin = Authorized(factory, actor.Token);
        Assert.Equal(HttpStatusCode.Conflict, (await admin.PatchAsync($"/api/admin/users/{actor.Id}/deactivate", null)).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await admin.GetAsync($"/api/admin/users/{Guid.NewGuid()}")).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await admin.PatchAsync($"/api/admin/users/{Guid.NewGuid()}/deactivate", null)).StatusCode);
        using (var scope = factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>(); (await db.Users.FindAsync(actor.Id))!.IsActive = false; await db.SaveChangesAsync();
        }
        Assert.Equal(HttpStatusCode.Unauthorized, (await admin.PatchAsync($"/api/admin/users/{Guid.NewGuid()}/deactivate", null)).StatusCode);
    }

    private static HttpClient Authorized(AuthApiFactory factory, string token)
    {
        var client = factory.CreateHttpsClient(); client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token); return client;
    }
    private static async Task<(Guid Id, string Email, string Token)> Account(AuthApiFactory factory, UserRole role)
    {
        var id = Guid.NewGuid(); var email = $"{id:N}@example.test";
        using (var scope = factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
            var user = new ApplicationUser { Id = id, FullName = $"Test {role}", Email = email, NormalizedEmail = email.ToUpperInvariant(), PhoneNumber = "+94770000000", Role = role, IsActive = true, CreatedAt = DateTimeOffset.UtcNow, UpdatedAt = DateTimeOffset.UtcNow };
            user.PasswordHash = scope.ServiceProvider.GetRequiredService<IPasswordHasher<ApplicationUser>>().HashPassword(user, Password);
            db.Users.Add(user); await db.SaveChangesAsync();
        }
        using var client = factory.CreateHttpsClient(); var response = await client.PostAsJsonAsync("/api/auth/login", new { email, password = Password });
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        return (id, email, (await response.Content.ReadFromJsonAsync<AuthResponseDto>())!.AccessToken);
    }
}
