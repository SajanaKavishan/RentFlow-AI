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

public sealed class TenantPropertyFavoritesTests
{
    private static readonly Guid TenantA = Guid.Parse("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");
    private static readonly Guid TenantB = Guid.Parse("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb");
    private static readonly Guid Landlord = Guid.Parse("cccccccc-cccc-cccc-cccc-cccccccccccc");

    [Fact]
    public async Task Endpoints_RequireTenantRole()
    {
        using var factory = new AuthApiFactory();
        using var anonymous = factory.CreateHttpsClient();
        using var landlord = AuthorizedClient(factory, Landlord, UserRole.Landlord);

        Assert.Equal(HttpStatusCode.Unauthorized, (await anonymous.GetAsync("/api/tenant/property-favorites")).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await landlord.GetAsync("/api/tenant/property-favorites")).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await landlord.PutAsync($"/api/tenant/property-favorites/{Guid.NewGuid()}", null)).StatusCode);
    }

    [Fact]
    public async Task Tenant_AddsReloadsAndRemovesFavoriteIdempotently()
    {
        using var factory = new AuthApiFactory();
        var propertyId = await SeedPropertyAsync(factory, available: true);
        using var client = AuthorizedClient(factory, TenantA, UserRole.Tenant);

        var firstAdd = await client.PutAsync($"/api/tenant/property-favorites/{propertyId}", null);
        var secondAdd = await client.PutAsync($"/api/tenant/property-favorites/{propertyId}", null);
        var saved = await client.GetFromJsonAsync<TenantPropertyFavoritesResponse>("/api/tenant/property-favorites");
        var remove = await client.DeleteAsync($"/api/tenant/property-favorites/{propertyId}");
        var afterRemove = await client.GetFromJsonAsync<TenantPropertyFavoritesResponse>("/api/tenant/property-favorites");

        Assert.Equal(HttpStatusCode.NoContent, firstAdd.StatusCode);
        Assert.Equal(HttpStatusCode.NoContent, secondAdd.StatusCode);
        Assert.NotNull(saved);
        Assert.Equal([propertyId], saved!.PropertyIds);
        Assert.Equal(HttpStatusCode.NoContent, remove.StatusCode);
        Assert.NotNull(afterRemove);
        Assert.Empty(afterRemove!.PropertyIds);
    }

    [Fact]
    public async Task Tenants_OnlyRetrieveAndModifyTheirOwnFavorites()
    {
        using var factory = new AuthApiFactory();
        var propertyId = await SeedPropertyAsync(factory, available: true);
        using var clientA = AuthorizedClient(factory, TenantA, UserRole.Tenant);
        using var clientB = AuthorizedClient(factory, TenantB, UserRole.Tenant);

        await clientA.PutAsync($"/api/tenant/property-favorites/{propertyId}", null);
        var tenantB = await clientB.GetFromJsonAsync<TenantPropertyFavoritesResponse>("/api/tenant/property-favorites");
        await clientB.DeleteAsync($"/api/tenant/property-favorites/{propertyId}");
        var tenantA = await clientA.GetFromJsonAsync<TenantPropertyFavoritesResponse>("/api/tenant/property-favorites");

        Assert.NotNull(tenantB);
        Assert.Empty(tenantB!.PropertyIds);
        Assert.NotNull(tenantA);
        Assert.Equal([propertyId], tenantA!.PropertyIds);
    }

    [Fact]
    public async Task Tenant_CannotFavoriteUnavailableOrUnknownProperty()
    {
        using var factory = new AuthApiFactory();
        var unavailableId = await SeedPropertyAsync(factory, available: false);
        using var client = AuthorizedClient(factory, TenantA, UserRole.Tenant);

        Assert.Equal(HttpStatusCode.NotFound, (await client.PutAsync($"/api/tenant/property-favorites/{unavailableId}", null)).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await client.PutAsync($"/api/tenant/property-favorites/{Guid.NewGuid()}", null)).StatusCode);
    }

    private static async Task<Guid> SeedPropertyAsync(AuthApiFactory factory, bool available)
    {
        factory.EnsureActiveUser(Landlord, UserRole.Landlord);
        using var scope = factory.Services.CreateScope();
        var context = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
        var property = new Property
        {
            LandlordId = Landlord,
            Title = "Favorite test property",
            Description = "A real available property.",
            Address = "1 Test Street",
            City = "Colombo",
            MonthlyRent = 100000,
            Bedrooms = 2,
            Bathrooms = 1,
            IsAvailable = available
        };
        context.Properties.Add(property);
        await context.SaveChangesAsync();
        return property.Id;
    }

    private static HttpClient AuthorizedClient(AuthApiFactory factory, Guid userId, UserRole role)
    {
        factory.EnsureActiveUser(userId, role);
        var client = factory.CreateHttpsClient();
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", CreateToken(userId, role));
        return client;
    }

    private static string CreateToken(Guid userId, UserRole role)
    {
        var credentials = new SigningCredentials(
            new SymmetricSecurityKey(Encoding.UTF8.GetBytes("test-only-signing-key-that-is-at-least-32-bytes-long")),
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
