using System.IdentityModel.Tokens.Jwt;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Claims;
using System.Text;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.IdentityModel.Tokens;
using RentFlow.Api.Data;
using RentFlow.Api.DTOs.ViewingFollowUps;
using RentFlow.Api.Models;
using RentFlow.Api.Tests.Services;
using Xunit;

namespace RentFlow.Api.Tests.Authentication;

public sealed class ViewingFollowUpEndpointsTests
{
    [Theory]
    [InlineData(UserRole.Landlord)] [InlineData(UserRole.Admin)] [InlineData(UserRole.MaintenanceTechnician)]
    public async Task TenantEndpoints_DenyOtherRoles(UserRole role)
    {
        using var factory = new AuthApiFactory(); using var client = Client(factory, Guid.NewGuid(), role);
        Assert.Equal(HttpStatusCode.Forbidden, (await client.PostAsync("/api/viewing-follow-ups/next/claim", null)).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await client.PostAsJsonAsync($"/api/viewing-follow-ups/{Guid.NewGuid()}/respond", new { decision = "NotNow" })).StatusCode);
    }
    [Fact]
    public async Task AnonymousCannotClaimOrRespond()
    {
        using var factory = new AuthApiFactory(); using var client = factory.CreateHttpsClient();
        Assert.Equal(HttpStatusCode.Unauthorized, (await client.PostAsync("/api/viewing-follow-ups/next/claim", null)).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await client.PostAsJsonAsync($"/api/viewing-follow-ups/{Guid.NewGuid()}/respond", new { decision = "NotNow" })).StatusCode);
    }
    [Fact]
    public async Task JwtOwnership_ClaimAndResponseContracts_NoClientIdentityOrClockTrusted()
    {
        var now = new DateTimeOffset(2030, 1, 2, 10, 0, 0, TimeSpan.Zero);
        using var factory = new AuthApiFactory(new ViewingCancellationTests.Clock(now));
        var tenant = Guid.NewGuid(); var other = Guid.NewGuid(); factory.EnsureActiveUser(tenant, UserRole.Tenant);
        var property = new Property { Title = "Authentic home", Address = "Real street", City = "Colombo" };
        var viewing = new ViewingRequest { TenantId = tenant, PropertyId = property.Id, RequestedDateTime = now.AddHours(-2), Status = ViewingStatus.Completed };
        using (var scope = factory.Services.CreateScope())
        { var db = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>(); db.AddRange(property, viewing); await db.SaveChangesAsync(); }
        using var stranger = Client(factory, other, UserRole.Tenant);
        Assert.Equal(HttpStatusCode.NoContent, (await stranger.PostAsJsonAsync("/api/viewing-follow-ups/next/claim", new { tenantId = tenant, serverNow = now.AddYears(1) })).StatusCode);
        using var owner = Client(factory, tenant, UserRole.Tenant);
        var response = await owner.PostAsJsonAsync("/api/viewing-follow-ups/next/claim", new { tenantId = other });
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var claim = (await response.Content.ReadFromJsonAsync<ViewingFollowUpDto>())!;
        Assert.Equal(viewing.Id, claim.ViewingId); Assert.Equal(property.Id, claim.Property.Id); Assert.Equal(now, claim.ClaimedAt);
        Assert.Equal("Authentic home", claim.Property.Title); Assert.True(claim.Application.CanApply);
        Assert.Equal(HttpStatusCode.NoContent, (await owner.PostAsync("/api/viewing-follow-ups/next/claim", null)).StatusCode);
        var path = $"/api/viewing-follow-ups/{claim.FollowUpId}/respond";
        Assert.Equal(HttpStatusCode.NotFound, (await stranger.PostAsJsonAsync(path, new { decision = "NotNow", tenantId = tenant })).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await owner.PostAsJsonAsync(path, new { decision = "0" })).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await owner.PostAsJsonAsync(path, new { decision = "ApplyNow", propertyId = Guid.NewGuid(), respondedAt = now.AddYears(1) })).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await owner.PostAsJsonAsync(path, new { decision = "ApplyNow" })).StatusCode);
        Assert.Equal(HttpStatusCode.Conflict, (await owner.PostAsJsonAsync(path, new { decision = "NotNow" })).StatusCode);
        using var checkScope = factory.Services.CreateScope(); var stored = checkScope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
        Assert.Empty(stored.RentalApplications); Assert.Equal(now, stored.ViewingFollowUps.Single().RespondedAt);
    }
    private static HttpClient Client(AuthApiFactory factory, Guid id, UserRole role)
    {
        factory.EnsureActiveUser(id, role); var client = factory.CreateHttpsClient();
        var token = new JwtSecurityToken(issuer: "RentFlow.Api.Tests", audience: "RentFlow.TestClients",
            claims: [new Claim(JwtRegisteredClaimNames.Sub, id.ToString()), new Claim("role", role.ToString()), new Claim("token_version", "0")],
            expires: DateTime.UtcNow.AddMinutes(10), signingCredentials: new SigningCredentials(new SymmetricSecurityKey(Encoding.UTF8.GetBytes("test-only-signing-key-that-is-at-least-32-bytes-long")), SecurityAlgorithms.HmacSha256));
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", new JwtSecurityTokenHandler().WriteToken(token)); return client;
    }
}
