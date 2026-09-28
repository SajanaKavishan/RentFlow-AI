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
using RentFlow.Api.DTOs.PropertyMatching;
using RentFlow.Api.Models;
using Xunit;

namespace RentFlow.Api.Tests.Authentication;

public sealed class TenantPropertyPreferencesTests
{
    private static readonly Guid TenantA = Guid.Parse("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");
    private static readonly Guid TenantB = Guid.Parse("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb");

    [Fact]
    public async Task Endpoints_RequireTenantRole()
    {
        using var factory = new AuthApiFactory();
        using var anonymous = factory.CreateHttpsClient();
        using var landlord = AuthorizedClient(factory, Guid.NewGuid(), UserRole.Landlord);

        Assert.Equal(
            HttpStatusCode.Unauthorized,
            (await anonymous.GetAsync("/api/tenant/property-preferences")).StatusCode);
        Assert.Equal(
            HttpStatusCode.Forbidden,
            (await landlord.GetAsync("/api/tenant/property-preferences")).StatusCode);
        Assert.Equal(
            HttpStatusCode.Forbidden,
            (await landlord.PutAsJsonAsync("/api/tenant/property-preferences", ValidRequest())).StatusCode);
        Assert.Equal(
            HttpStatusCode.Unauthorized,
            (await anonymous.GetAsync("/api/properties/matches")).StatusCode);
        Assert.Equal(
            HttpStatusCode.Forbidden,
            (await landlord.PostAsJsonAsync("/api/properties/match", ValidRequest())).StatusCode);
    }

    [Fact]
    public async Task Tenant_CreatesUpdatesAndReloadsOwnPersistedPreferences()
    {
        using var factory = new AuthApiFactory();
        using var client = AuthorizedClient(factory, TenantA, UserRole.Tenant);

        var initial = await client.GetFromJsonAsync<TenantPropertyPreferenceResponse>(
            "/api/tenant/property-preferences");
        var createdResponse = await client.PutAsJsonAsync(
            "/api/tenant/property-preferences",
            new
            {
                preferredCity = "  Kurunegala ",
                maximumMonthlyRent = 150000,
                minimumBedrooms = 2,
                minimumBathrooms = 2,
                preferredAmenities = new[] { " Parking ", "Security", "parking" }
            });
        var created = await createdResponse.Content
            .ReadFromJsonAsync<TenantPropertyPreferenceResponse>();
        var reloaded = await client.GetFromJsonAsync<TenantPropertyPreferenceResponse>(
            "/api/tenant/property-preferences");

        Assert.NotNull(initial);
        Assert.False(initial!.IsConfigured);
        Assert.Equal(HttpStatusCode.OK, createdResponse.StatusCode);
        Assert.NotNull(created);
        Assert.True(created!.IsConfigured);
        Assert.Equal("Kurunegala", created.PreferredCity);
        Assert.Equal(["Parking", "Security"], created.PreferredAmenities);
        Assert.NotNull(reloaded);
        Assert.Equal(created.PreferredCity, reloaded!.PreferredCity);
        Assert.Equal(created.MaximumMonthlyRent, reloaded.MaximumMonthlyRent);

        var updatedResponse = await client.PutAsJsonAsync(
            "/api/tenant/property-preferences",
            new
            {
                preferredCity = "Colombo",
                maximumMonthlyRent = 175000,
                preferredAmenities = Array.Empty<string>()
            });

        Assert.Equal(HttpStatusCode.OK, updatedResponse.StatusCode);
        using var scope = factory.Services.CreateScope();
        var context = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
        var records = await context.TenantPropertyPreferences.ToListAsync();
        Assert.Single(records);
        Assert.Equal("Colombo", records[0].PreferredCity);
        Assert.Equal(175000m, records[0].MaximumMonthlyRent);
    }

    [Fact]
    public async Task SpoofedUserId_CannotReadOrModifyAnotherTenant()
    {
        using var factory = new AuthApiFactory();
        using var clientA = AuthorizedClient(factory, TenantA, UserRole.Tenant);
        using var clientB = AuthorizedClient(factory, TenantB, UserRole.Tenant);

        var response = await clientA.PutAsJsonAsync(
            "/api/tenant/property-preferences",
            new
            {
                userId = TenantB,
                preferredCity = "Galle",
                maximumMonthlyRent = 90000,
                preferredAmenities = new[] { "Parking" }
            });
        var tenantBPreferences = await clientB
            .GetFromJsonAsync<TenantPropertyPreferenceResponse>(
                "/api/tenant/property-preferences");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.NotNull(tenantBPreferences);
        Assert.False(tenantBPreferences!.IsConfigured);
        using var scope = factory.Services.CreateScope();
        var stored = await scope.ServiceProvider
            .GetRequiredService<ApplicationDbContext>()
            .TenantPropertyPreferences.SingleAsync();
        Assert.Equal(TenantA, stored.UserId);
    }

    [Theory]
    [InlineData(-1, 2, 2)]
    [InlineData(1000, -1, 2)]
    [InlineData(1000, 2, 21)]
    public async Task Update_RejectsInvalidNumericPreferences(
        decimal maximumRent,
        int bedrooms,
        int bathrooms)
    {
        using var factory = new AuthApiFactory();
        using var client = AuthorizedClient(factory, TenantA, UserRole.Tenant);

        var response = await client.PutAsJsonAsync(
            "/api/tenant/property-preferences",
            new
            {
                maximumMonthlyRent = maximumRent,
                minimumBedrooms = bedrooms,
                minimumBathrooms = bathrooms,
                preferredAmenities = Array.Empty<string>()
            });

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task Delete_RemovesSavedPreferences()
    {
        using var factory = new AuthApiFactory();
        using var client = AuthorizedClient(factory, TenantA, UserRole.Tenant);
        await client.PutAsJsonAsync("/api/tenant/property-preferences", ValidRequest());

        var delete = await client.DeleteAsync("/api/tenant/property-preferences");
        var reloaded = await client.GetFromJsonAsync<TenantPropertyPreferenceResponse>(
            "/api/tenant/property-preferences");

        Assert.Equal(HttpStatusCode.NoContent, delete.StatusCode);
        Assert.NotNull(reloaded);
        Assert.False(reloaded!.IsConfigured);
    }

    private static object ValidRequest() => new
    {
        preferredCity = "Kurunegala",
        maximumMonthlyRent = 150000,
        minimumBedrooms = 2,
        minimumBathrooms = 2,
        preferredAmenities = new[] { "Parking", "Security" }
    };

    private static HttpClient AuthorizedClient(
        AuthApiFactory factory,
        Guid userId,
        UserRole role)
    {
        factory.EnsureActiveUser(userId, role);
        var client = factory.CreateHttpsClient();
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue(
            "Bearer",
            CreateToken(userId, role));
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
                new Claim("role", role.ToString()),
                new Claim("token_version", "0")
            ],
            expires: DateTime.UtcNow.AddMinutes(10),
            signingCredentials: credentials);
        return new JwtSecurityTokenHandler().WriteToken(token);
    }
}
