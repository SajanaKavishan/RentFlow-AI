using System.IdentityModel.Tokens.Jwt;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Claims;
using System.Text;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.IdentityModel.Tokens;
using RentFlow.Api.Data;
using RentFlow.Api.Models;
using Xunit;

namespace RentFlow.Api.Tests.Authentication;

public sealed class ViewingTenantSummaryEndpointsTests
{
    private static readonly Guid LandlordId = Guid.NewGuid();
    private static readonly Guid TenantId = Guid.NewGuid();
    private const string Phone = "+94 77 123 4567";

    [Theory]
    [InlineData(ViewingStatus.Pending, false)]
    [InlineData(ViewingStatus.Approved, true)]
    [InlineData(ViewingStatus.Rejected, false)]
    [InlineData(ViewingStatus.Cancelled, false)]
    [InlineData(ViewingStatus.Completed, false)]
    public async Task OwningLandlord_DetailDisclosesOnlySafeSummary(ViewingStatus status, bool phoneVisible)
    {
        using var factory = new AuthApiFactory();
        var viewing = await SeedAsync(factory, status);
        using var client = Client(factory, LandlordId, UserRole.Landlord);
        using var response = await client.GetAsync($"/api/viewings/{viewing.Id}");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        var tenant = json.RootElement.GetProperty("tenant");
        Assert.Equal(new[] { "displayName", "phoneNumber" },
            tenant.EnumerateObject().Select(p => p.Name).Order().ToArray());
        Assert.Equal("Chamodya Sayanjali", tenant.GetProperty("displayName").GetString());
        Assert.Equal(phoneVisible ? Phone : null, tenant.GetProperty("phoneNumber").GetString());
        Assert.DoesNotContain("tenant-private@example.test", json.RootElement.GetRawText());
        Assert.DoesNotContain("secret-hash", json.RootElement.GetRawText());
        if (!phoneVisible) Assert.DoesNotContain(Phone, json.RootElement.GetRawText());
    }

    [Theory]
    [InlineData(UserRole.Tenant)]
    [InlineData(UserRole.Admin)]
    public async Task TenantAndAdmin_ApprovedDetailDoesNotGainContactDisclosure(UserRole role)
    {
        using var factory = new AuthApiFactory();
        var viewing = await SeedAsync(factory, ViewingStatus.Approved);
        using var client = Client(factory, role == UserRole.Tenant ? TenantId : Guid.NewGuid(), role);
        using var response = await client.GetAsync($"/api/viewings/{viewing.Id}");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        Assert.Equal("Chamodya Sayanjali", json.RootElement.GetProperty("tenant").GetProperty("displayName").GetString());
        Assert.Null(json.RootElement.GetProperty("tenant").GetProperty("phoneNumber").GetString());
        Assert.DoesNotContain(Phone, json.RootElement.GetRawText());
    }

    [Theory]
    [InlineData(UserRole.Landlord)]
    [InlineData(UserRole.Admin)]
    [InlineData(UserRole.Tenant)]
    public async Task Lists_ReturnNameWithoutPhoneEvenWhenApproved(UserRole role)
    {
        using var factory = new AuthApiFactory();
        var viewing = await SeedAsync(factory, ViewingStatus.Approved);
        var userId = role == UserRole.Landlord ? LandlordId : role == UserRole.Tenant ? TenantId : Guid.NewGuid();
        using var client = Client(factory, userId, role);
        using var response = await client.GetAsync(role == UserRole.Tenant
            ? "/api/viewings" : $"/api/viewings/property/{viewing.PropertyId}");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        var tenant = json.RootElement[0].GetProperty("tenant");
        Assert.Equal("Chamodya Sayanjali", tenant.GetProperty("displayName").GetString());
        Assert.Null(tenant.GetProperty("phoneNumber").GetString());
        Assert.DoesNotContain(Phone, json.RootElement.GetRawText());
    }

    [Theory]
    [InlineData(UserRole.Landlord)]
    [InlineData(UserRole.Tenant)]
    public async Task UnrelatedUser_CannotReadApprovedViewing(UserRole role)
    {
        using var factory = new AuthApiFactory();
        var viewing = await SeedAsync(factory, ViewingStatus.Approved);
        using var client = Client(factory, Guid.NewGuid(), role);
        using var response = await client.GetAsync($"/api/viewings/{viewing.Id}");
        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
        Assert.DoesNotContain(Phone, await response.Content.ReadAsStringAsync());
        if (role == UserRole.Landlord)
        {
            using var list = await client.GetAsync($"/api/viewings/property/{viewing.PropertyId}");
            Assert.Equal(HttpStatusCode.NotFound, list.StatusCode);
            using var approve = await client.PatchAsJsonAsync($"/api/viewings/{viewing.Id}/approve", new { });
            Assert.Equal(HttpStatusCode.NotFound, approve.StatusCode);
        }
    }

    [Fact]
    public async Task Anonymous_CannotReadViewing()
    {
        using var factory = new AuthApiFactory();
        var viewing = await SeedAsync(factory, ViewingStatus.Approved);
        using var client = factory.CreateHttpsClient();
        using var response = await client.GetAsync($"/api/viewings/{viewing.Id}");
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
        Assert.DoesNotContain(Phone, await response.Content.ReadAsStringAsync());
    }

    [Theory]
    [InlineData("", "")]
    [InlineData("   ", "   ")]
    [InlineData("Chamodya Sayanjali", "invalid-number")]
    [InlineData("Chamodya Sayanjali", "+12")]
    [InlineData("Chamodya Sayanjali", "tel:+94771234567")]
    public async Task MissingNameOrInvalidPhone_UsesTruthfulFallback(string name, string phone)
    {
        using var factory = new AuthApiFactory();
        var viewing = await SeedAsync(factory, ViewingStatus.Approved, name, phone);
        using var client = Client(factory, LandlordId, UserRole.Landlord);
        using var response = await client.GetAsync($"/api/viewings/{viewing.Id}");
        response.EnsureSuccessStatusCode();
        using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        var tenant = json.RootElement.GetProperty("tenant");
        Assert.Equal(string.IsNullOrWhiteSpace(name) ? "Tenant" : name, tenant.GetProperty("displayName").GetString());
        Assert.Null(tenant.GetProperty("phoneNumber").GetString());
    }

    [Fact]
    public async Task MissingTenantRecord_UsesFallbackWithoutPhone()
    {
        using var factory = new AuthApiFactory();
        var viewing = await SeedAsync(factory, ViewingStatus.Approved);
        using (var scope = factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
            db.Users.Remove(await db.Users.SingleAsync(u => u.Id == TenantId));
            await db.SaveChangesAsync();
        }
        using var client = Client(factory, LandlordId, UserRole.Landlord);
        using var response = await client.GetAsync($"/api/viewings/{viewing.Id}");
        response.EnsureSuccessStatusCode();
        using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        Assert.Equal("Tenant", json.RootElement.GetProperty("tenant").GetProperty("displayName").GetString());
        Assert.Null(json.RootElement.GetProperty("tenant").GetProperty("phoneNumber").GetString());
    }

    [Theory]
    [InlineData("approve", true)]
    [InlineData("reject", false)]
    public async Task TransitionAndRefetch_ApplyContactPolicy(string transition, bool visible)
    {
        using var factory = new AuthApiFactory();
        var viewing = await SeedAsync(factory, ViewingStatus.Pending);
        using var landlord = Client(factory, LandlordId, UserRole.Landlord);
        using var changed = await landlord.PatchAsJsonAsync($"/api/viewings/{viewing.Id}/{transition}",
            new { landlordResponse = "Confirmed response" });
        changed.EnsureSuccessStatusCode();
        using var fetched = await landlord.GetAsync($"/api/viewings/{viewing.Id}");
        fetched.EnsureSuccessStatusCode();
        foreach (var response in new[] { changed, fetched })
        {
            using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
            Assert.Equal(visible ? Phone : null, json.RootElement.GetProperty("tenant").GetProperty("phoneNumber").GetString());
        }
        if (visible)
        {
            using var tenant = Client(factory, TenantId, UserRole.Tenant);
            using var cancelled = await tenant.PatchAsync($"/api/viewings/{viewing.Id}/cancel", null);
            cancelled.EnsureSuccessStatusCode();
            using var refetched = await landlord.GetAsync($"/api/viewings/{viewing.Id}");
            refetched.EnsureSuccessStatusCode();
            foreach (var response in new[] { cancelled, refetched })
            {
                using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
                Assert.Null(json.RootElement.GetProperty("tenant").GetProperty("phoneNumber").GetString());
            }
        }
    }

    [Fact]
    public async Task Refetch_ResolvesCurrentProfileNameAndPhone()
    {
        using var factory = new AuthApiFactory();
        var viewing = await SeedAsync(factory, ViewingStatus.Approved);
        using (var scope = factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
            var user = await db.Users.SingleAsync(u => u.Id == TenantId);
            user.FullName = "  Updated tenant name  ";
            user.PhoneNumber = "  +441234567890  ";
            await db.SaveChangesAsync();
        }
        using var client = Client(factory, LandlordId, UserRole.Landlord);
        using var response = await client.GetAsync($"/api/viewings/{viewing.Id}");
        response.EnsureSuccessStatusCode();
        using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        Assert.Equal("Updated tenant name", json.RootElement.GetProperty("tenant").GetProperty("displayName").GetString());
        Assert.Equal("+441234567890", json.RootElement.GetProperty("tenant").GetProperty("phoneNumber").GetString());
    }

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

    private static async Task<ViewingRequest> SeedAsync(AuthApiFactory factory, ViewingStatus status,
        string name = "  Chamodya Sayanjali  ", string phone = Phone)
    {
        factory.EnsureActiveUser(LandlordId, UserRole.Landlord);
        factory.EnsureActiveUser(TenantId, UserRole.Tenant);
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
        var tenant = await db.Users.SingleAsync(u => u.Id == TenantId);
        tenant.FullName = name;
        tenant.PhoneNumber = phone;
        tenant.Email = "tenant-private@example.test";
        tenant.PasswordHash = "secret-hash";
        var property = new Property
        {
            Id = Guid.NewGuid(), LandlordId = LandlordId, Title = "Harbour view residences",
            Address = "Kureepoththa, Pothuhera", City = "Kurunegala", Description = "Viewing test",
            IsAvailable = true, MonthlyRent = 100000m, Bedrooms = 2, Bathrooms = 1
        };
        var viewing = new ViewingRequest
        {
            Id = Guid.NewGuid(), PropertyId = property.Id, TenantId = TenantId,
            Status = status, RequestedDateTime = DateTimeOffset.UtcNow.AddDays(5),
            DurationMinutes = 30, CreatedAt = DateTimeOffset.UtcNow
        };
        db.Properties.Add(property);
        db.ViewingRequests.Add(viewing);
        await db.SaveChangesAsync();
        return viewing;
    }
}
