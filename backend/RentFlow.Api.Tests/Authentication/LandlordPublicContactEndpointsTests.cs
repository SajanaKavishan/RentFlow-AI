using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Migrations.Operations;
using Microsoft.Extensions.DependencyInjection;
using RentFlow.Api.Data;
using RentFlow.Api.Data.Migrations;
using RentFlow.Api.Models;
using RentFlow.Api.Services.Interfaces;
using Xunit;

namespace RentFlow.Api.Tests.Authentication;

public sealed class LandlordPublicContactEndpointsTests
{
    private const string PublicPhone = "+94 77 123 4567";

    [Fact]
    public void DefaultsAndMigration_DoNotCopyPrivatePhone()
    {
        var user = new ApplicationUser { PhoneNumber = "+94112223344" };
        Assert.False(user.PublicContactEnabled);
        Assert.Null(user.PublicContactPhone);
        var operations = new AddLandlordPublicContact().UpOperations;
        Assert.Equal(2, operations.Count);
        var columns = operations.Cast<AddColumnOperation>().ToArray();
        Assert.All(columns, column => Assert.Equal("Users", column.Table));
        Assert.Null(columns.Single(c => c.Name == "PublicContactPhone").DefaultValue);
        Assert.True(columns.Single(c => c.Name == "PublicContactPhone").IsNullable);
        Assert.Equal(false, columns.Single(c => c.Name == "PublicContactEnabled").DefaultValue);
    }

    [Fact]
    public async Task Owner_CanPublishChangeDisableAndClear_WithoutChangingPrivatePhone()
    {
        await using var factory = new AuthApiFactory();
        var (landlord, property) = Seed(factory);
        using var owner = Client(factory, landlord.Id, UserRole.Landlord);
        using var tenant = Client(factory, Guid.NewGuid(), UserRole.Tenant);
        using var initial = await owner.GetAsync("/api/auth/me");
        var initialProfile = await initial.Content.ReadFromJsonAsync<JsonElement>();
        Assert.False(initialProfile.GetProperty("publicContactEnabled").GetBoolean());
        Assert.False(initialProfile.TryGetProperty("publicContactPhone", out _));

        foreach (var phone in new[] { "  " + PublicPhone + "  ", "+44 (20) 7123-4567" })
        {
            using var saved = await Save(owner, phone, true);
            Assert.Equal(HttpStatusCode.OK, saved.StatusCode);
            using var contact = await tenant.GetAsync($"/api/properties/{property}/landlord-contact");
            Assert.Equal(HttpStatusCode.OK, contact.StatusCode);
            Assert.True(contact.Headers.CacheControl?.NoStore);
            var payload = await contact.Content.ReadFromJsonAsync<JsonElement>();
            Assert.Equal(new[] { "displayName", "phoneNumber" }, payload.EnumerateObject().Select(p => p.Name).Order());
            Assert.Equal(phone.Trim(), payload.GetProperty("phoneNumber").GetString());
            Assert.DoesNotContain(landlord.PhoneNumber, payload.GetRawText());
            // Anonymous identity never grows contact fields, even while contact is enabled.
            using var anonymous = factory.CreateHttpsClient();
            var summary = await anonymous.GetFromJsonAsync<JsonElement>($"/api/properties/{property}/landlord-summary");
            Assert.Equal(new[] { "displayName", "hasProfileImage", "memberSinceYear" }, summary.EnumerateObject().Select(p => p.Name).Order());
        }

        // Older clients omitting contact fields must preserve opt-in settings.
        using var legacy = await owner.PutAsJsonAsync("/api/auth/profile", new { fullName = "Updated Landlord", phoneNumber = landlord.PhoneNumber });
        legacy.EnsureSuccessStatusCode();
        using var disabled = await Save(owner, "+44 (20) 7123-4567", false);
        disabled.EnsureSuccessStatusCode();
        using var hidden = await tenant.GetAsync($"/api/properties/{property}/landlord-contact");
        Assert.Equal(HttpStatusCode.NoContent, hidden.StatusCode);
        using var clear = await Save(owner, "", false);
        clear.EnsureSuccessStatusCode();
        using var scope = factory.Services.CreateScope();
        var stored = await scope.ServiceProvider.GetRequiredService<ApplicationDbContext>().Users.SingleAsync(u => u.Id == landlord.Id);
        Assert.Equal(landlord.PhoneNumber, stored.PhoneNumber);
        Assert.Null(stored.PublicContactPhone);
        Assert.False(stored.PublicContactEnabled);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData("invalid number")]
    [InlineData("+94 1")]
    [InlineData("1234567890123456")]
    [InlineData("+94771234567;ext=22")]
    [InlineData("+94---------------------------------771234567")]
    public async Task EnabledInvalidPhone_IsRejectedWithoutPartialProfileUpdate(string? phone)
    {
        await using var factory = new AuthApiFactory();
        var (landlord, _) = Seed(factory);
        using var owner = Client(factory, landlord.Id, UserRole.Landlord);
        using var response = await Save(owner, phone, true);
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        using var scope = factory.Services.CreateScope();
        var stored = await scope.ServiceProvider.GetRequiredService<ApplicationDbContext>().Users.SingleAsync(u => u.Id == landlord.Id);
        Assert.Equal("Test Landlord", stored.FullName);
        Assert.Null(stored.PublicContactPhone);
        Assert.False(stored.PublicContactEnabled);
    }

    [Theory]
    [InlineData(UserRole.Tenant)]
    [InlineData(UserRole.Admin)]
    [InlineData(UserRole.MaintenanceTechnician)]
    public async Task OtherRoles_CannotEditPublicContact(UserRole role)
    {
        await using var factory = new AuthApiFactory();
        using var client = Client(factory, Guid.NewGuid(), role);
        foreach (var enabled in new[] { true, false })
        {
            using var response = await Save(client, PublicPhone, enabled);
            Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        }
        var profile = await client.GetFromJsonAsync<JsonElement>("/api/auth/me");
        Assert.False(profile.TryGetProperty("publicContactPhone", out _));
        Assert.False(profile.TryGetProperty("publicContactEnabled", out _));
    }

    [Theory]
    [InlineData(false, "+94 77 123 4567")]
    [InlineData(true, null)]
    [InlineData(true, "")]
    [InlineData(true, "invalid")]
    [InlineData(true, "12-----")]
    public async Task UnavailableContact_DoesNotFallBackToAccountPhone(bool enabled, string? phone)
    {
        await using var factory = new AuthApiFactory();
        var (_, property) = Seed(factory, enabled: enabled, phone: phone);
        using var client = Client(factory, Guid.NewGuid(), UserRole.Tenant);
        using var response = await client.GetAsync($"/api/properties/{property}/landlord-contact");
        Assert.Equal(HttpStatusCode.NoContent, response.StatusCode);
        Assert.Empty(await response.Content.ReadAsStringAsync());
    }

    [Theory]
    [InlineData(false, UserRole.Landlord)]
    [InlineData(true, UserRole.Admin)]
    [InlineData(true, UserRole.Tenant)]
    public async Task InvalidOwnerAndUnknownProperty_AreSafeFailures(bool active, UserRole role)
    {
        await using var factory = new AuthApiFactory();
        var (_, property) = Seed(factory, active, role, true, PublicPhone);
        using var client = Client(factory, Guid.NewGuid(), UserRole.Tenant);
        foreach (var id in new[] { property, Guid.NewGuid() })
        {
            using var response = await client.GetAsync($"/api/properties/{id}/landlord-contact");
            Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
            Assert.DoesNotContain(PublicPhone, await response.Content.ReadAsStringAsync());
        }
    }

    [Theory]
    [InlineData(null, HttpStatusCode.Unauthorized)]
    [InlineData(UserRole.Landlord, HttpStatusCode.Forbidden)]
    [InlineData(UserRole.Admin, HttpStatusCode.Forbidden)]
    [InlineData(UserRole.MaintenanceTechnician, HttpStatusCode.Forbidden)]
    public async Task Endpoint_IsAuthenticatedTenantOnly(UserRole? role, HttpStatusCode expected)
    {
        await using var factory = new AuthApiFactory();
        var (_, property) = Seed(factory, enabled: true, phone: PublicPhone);
        using var client = role.HasValue ? Client(factory, Guid.NewGuid(), role.Value) : factory.CreateHttpsClient();
        using var response = await client.GetAsync($"/api/properties/{property}/landlord-contact");
        Assert.Equal(expected, response.StatusCode);
        Assert.DoesNotContain(PublicPhone, await response.Content.ReadAsStringAsync());
    }

    private static Task<HttpResponseMessage> Save(HttpClient client, string? phone, bool enabled) =>
        client.PutAsJsonAsync("/api/auth/profile", new { fullName = "Updated Landlord", phoneNumber = "+94770000000", publicContactPhone = phone, publicContactEnabled = enabled });

    private static HttpClient Client(AuthApiFactory factory, Guid id, UserRole role)
    {
        factory.EnsureActiveUser(id, role);
        using var scope = factory.Services.CreateScope();
        var user = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>().Users.Single(u => u.Id == id);
        var token = scope.ServiceProvider.GetRequiredService<IJwtTokenService>().CreateToken(user);
        var client = factory.CreateHttpsClient();
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token.Value);
        return client;
    }

    private static (ApplicationUser, Guid) Seed(AuthApiFactory factory, bool active = true, UserRole role = UserRole.Landlord, bool enabled = false, string? phone = null)
    {
        var id = Guid.NewGuid();
        factory.EnsureActiveUser(id, role);
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
        var user = db.Users.Single(u => u.Id == id);
        user.IsActive = active;
        user.PublicContactEnabled = enabled;
        user.PublicContactPhone = phone;
        var property = new Property { Id = Guid.NewGuid(), Landlord = user, LandlordId = id, Title = "Test home", Address = "1 Test Road", City = "Colombo", IsAvailable = true };
        db.Properties.Add(property);
        db.SaveChanges();
        return (user, property.Id);
    }
}
