using System.IdentityModel.Tokens.Jwt;
using System.Net;
using System.Net.Http.Headers;
using System.Security.Claims;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.IdentityModel.Tokens;
using RentFlow.Api.Data;
using RentFlow.Api.Models;
using Xunit;

namespace RentFlow.Api.Tests.Authentication;

public sealed class RentalApplicationActionCountsEndpointsTests
{
    [Theory]
    [InlineData(RentalApplicationStatus.Draft, false)]
    [InlineData(RentalApplicationStatus.Submitted, true)]
    [InlineData(RentalApplicationStatus.UnderReview, true)]
    [InlineData(RentalApplicationStatus.ChangesRequested, false)]
    [InlineData(RentalApplicationStatus.Approved, false)]
    [InlineData(RentalApplicationStatus.Rejected, false)]
    [InlineData(RentalApplicationStatus.Withdrawn, false)]
    public async Task ExactLifecycleStatus_DeterminesLandlordAttention(RentalApplicationStatus status, bool requiresAction)
    {
        using var factory = new AuthApiFactory();
        var owner = Guid.NewGuid();
        using var client = Client(factory, owner, UserRole.Landlord);
        var property = new Property { LandlordId = owner, Title = "Lifecycle test" };
        using (var scope = factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
            db.Properties.Add(property);
            db.RentalApplications.Add(Request(property.Id, status));
            await db.SaveChangesAsync();
        }
        using var response = await client.GetAsync("/api/rental-applications/mine/action-counts");
        response.EnsureSuccessStatusCode();
        using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        if (requiresAction)
        {
            Assert.Single(json.RootElement.EnumerateArray());
            Assert.Equal(property.Id, json.RootElement[0].GetProperty("propertyId").GetGuid());
            Assert.Equal(1, json.RootElement[0].GetProperty("actionRequiredCount").GetInt32());
        }
        else Assert.Empty(json.RootElement.EnumerateArray());
    }

    [Fact]
    public async Task Summary_GroupsOnlyActionRequiredOwnedApplications_AndIgnoresCallerLandlordId()
    {
        using var factory = new AuthApiFactory();
        var owner = Guid.NewGuid();
        var other = Guid.NewGuid();
        factory.EnsureActiveUser(owner, UserRole.Landlord);
        factory.EnsureActiveUser(other, UserRole.Landlord);
        var first = new Property { LandlordId = owner, Title = "First" };
        var second = new Property { LandlordId = owner, Title = "Second" };
        var empty = new Property { LandlordId = owner, Title = "Empty" };
        var noAction = new Property { LandlordId = owner, Title = "No action required" };
        var foreign = new Property { LandlordId = other, Title = "Other landlord" };
        using (var scope = factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
            db.Properties.AddRange(first, second, empty, noAction, foreign);
            db.RentalApplications.AddRange(Request(first.Id), Request(first.Id, RentalApplicationStatus.UnderReview), Request(second.Id), Request(foreign.Id));
            foreach (var status in Enum.GetValues<RentalApplicationStatus>().Where(status => status != RentalApplicationStatus.Submitted && status != RentalApplicationStatus.UnderReview))
            {
                db.RentalApplications.Add(Request(first.Id, status));
                db.RentalApplications.Add(Request(noAction.Id, status));
            }
            // A missing property cannot contribute to the portfolio summary.
            db.RentalApplications.Add(Request(Guid.NewGuid()));
            await db.SaveChangesAsync();
        }

        using var client = Client(factory, owner, UserRole.Landlord);
        using var response = await client.GetAsync($"/api/rental-applications/mine/action-counts?landlordId={other}");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        var rows = json.RootElement.EnumerateArray().ToArray();
        Assert.Equal(2, rows.Length);
        var counts = rows.ToDictionary(row => row.GetProperty("propertyId").GetGuid(), row => row.GetProperty("actionRequiredCount").GetInt32());
        Assert.Equal(2, counts[first.Id]);
        Assert.Equal(1, counts[second.Id]);
        Assert.DoesNotContain(foreign.Id, counts.Keys);
        Assert.DoesNotContain(empty.Id, counts.Keys);
        Assert.DoesNotContain(noAction.Id, counts.Keys);
        foreach (var row in rows)
            Assert.Equal(new[] { "actionRequiredCount", "propertyId" }, row.EnumerateObject().Select(property => property.Name).Order().ToArray());
        Assert.DoesNotContain("Private tenant message", json.RootElement.GetRawText());

        using var otherClient = Client(factory, other, UserRole.Landlord);
        using var otherResponse = await otherClient.GetAsync("/api/rental-applications/mine/action-counts");
        otherResponse.EnsureSuccessStatusCode();
        using var otherJson = JsonDocument.Parse(await otherResponse.Content.ReadAsStringAsync());
        Assert.Single(otherJson.RootElement.EnumerateArray());
        Assert.Equal(foreign.Id, otherJson.RootElement[0].GetProperty("propertyId").GetGuid());
    }

    [Fact]
    public async Task LandlordWithoutProperties_GetsEmptySummary()
    {
        using var factory = new AuthApiFactory();
        using var client = Client(factory, Guid.NewGuid(), UserRole.Landlord);
        using var response = await client.GetAsync("/api/rental-applications/mine/action-counts");
        response.EnsureSuccessStatusCode();
        Assert.Equal("[]", await response.Content.ReadAsStringAsync());
    }

    [Theory]
    [InlineData(UserRole.Tenant)]
    [InlineData(UserRole.Admin)]
    [InlineData(UserRole.MaintenanceTechnician)]
    public async Task NonLandlord_IsForbidden(UserRole role)
    {
        using var factory = new AuthApiFactory();
        using var client = Client(factory, Guid.NewGuid(), role);
        using var response = await client.GetAsync("/api/rental-applications/mine/action-counts");
        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Fact]
    public async Task Anonymous_IsUnauthorized()
    {
        using var factory = new AuthApiFactory();
        using var client = factory.CreateHttpsClient();
        using var response = await client.GetAsync("/api/rental-applications/mine/action-counts");
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    private static RentalApplication Request(Guid propertyId, RentalApplicationStatus status = RentalApplicationStatus.Submitted) => new()
    {
        PropertyId = propertyId, TenantId = Guid.NewGuid(), Status = status,
        TenantNote = "Private tenant message"
    };

    private static HttpClient Client(AuthApiFactory factory, Guid id, UserRole role)
    {
        factory.EnsureActiveUser(id, role);
        var client = factory.CreateHttpsClient();
        var token = new JwtSecurityToken(
            issuer: "RentFlow.Api.Tests", audience: "RentFlow.TestClients",
            claims: [new Claim(JwtRegisteredClaimNames.Sub, id.ToString()), new Claim("role", role.ToString()), new Claim("token_version", "0")],
            expires: DateTime.UtcNow.AddMinutes(10),
            signingCredentials: new SigningCredentials(new SymmetricSecurityKey(
                Encoding.UTF8.GetBytes("test-only-signing-key-that-is-at-least-32-bytes-long")), SecurityAlgorithms.HmacSha256));
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", new JwtSecurityTokenHandler().WriteToken(token));
        return client;
    }
}
