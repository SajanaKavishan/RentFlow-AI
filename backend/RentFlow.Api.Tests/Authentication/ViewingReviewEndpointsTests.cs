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
using RentFlow.Api.DTOs.ViewingReviews;
using RentFlow.Api.Models;
using Xunit;

namespace RentFlow.Api.Tests.Authentication;

public sealed class ViewingReviewEndpointsTests
{
    [Theory]
    [InlineData(UserRole.Tenant)] [InlineData(UserRole.Admin)] [InlineData(UserRole.MaintenanceTechnician)]
    public async Task LandlordSummary_RejectsOtherRolesAndAnonymous(UserRole role)
    {
        using var factory = new AuthApiFactory(); using var client = Client(factory, Guid.NewGuid(), role);
        using var anonymous = factory.CreateHttpsClient();
        const string path = "/api/landlord/viewing-reviews/summary";
        Assert.Equal(HttpStatusCode.Forbidden, (await client.GetAsync(path)).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await anonymous.GetAsync(path)).StatusCode);
    }
    [Fact]
    public async Task LandlordSummary_JwtScopeGroupingAndSafeReadOnlyContract()
    {
        using var factory = new AuthApiFactory(); var landlord = Guid.NewGuid(); var tenant = Guid.NewGuid();
        using var owner = Client(factory, landlord, UserRole.Landlord);
        using var stranger = Client(factory, Guid.NewGuid(), UserRole.Landlord);
        factory.EnsureActiveUser(tenant, UserRole.Tenant);
        var property = new Property { LandlordId = landlord, Title = "Owned home" };
        var viewing = new ViewingRequest { TenantId = tenant, PropertyId = property.Id, Status = ViewingStatus.Completed };
        using (var scope = factory.Services.CreateScope()) {
            var db = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
            db.AddRange(property, viewing); await db.SaveChangesAsync();
            await new RentFlow.Api.Services.ViewingReviewService(db, TimeProvider.System).SaveAsync(tenant, viewing.Id, new() { PropertyRating = 2, LandlordRating = 5, Comment = "Safe feedback" });
        }
        const string path = "/api/landlord/viewing-reviews/summary";
        var response = await owner.GetAsync(path); Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        using var document = JsonDocument.Parse(await response.Content.ReadAsStringAsync()); var root = document.RootElement;
        Assert.Equal(new[] { "landlord", "properties" }, root.EnumerateObject().Select(p => p.Name));
        Assert.Equal(5, root.GetProperty("landlord").GetProperty("averageRating").GetDouble());
        var feedback = root.GetProperty("properties")[0];
        Assert.Equal(new[] { "propertyId", "title", "averageRating", "reviewCount", "recentReviews" }, feedback.EnumerateObject().Select(p => p.Name));
        Assert.Equal(property.Id, feedback.GetProperty("propertyId").GetGuid()); Assert.Equal(2, feedback.GetProperty("averageRating").GetDouble());
        Assert.Equal(new[] { "rating", "comment", "reviewMonth" }, feedback.GetProperty("recentReviews")[0].EnumerateObject().Select(p => p.Name));
        var other = (await stranger.GetFromJsonAsync<LandlordViewingReviewSummaryDto>($"{path}?landlordId={landlord}"))!;
        Assert.Empty(other.Properties); Assert.Equal(0, other.Landlord.ReviewCount);
        Assert.Equal(HttpStatusCode.MethodNotAllowed, (await owner.DeleteAsync(path)).StatusCode);
        Assert.Equal(HttpStatusCode.MethodNotAllowed, (await owner.PutAsJsonAsync(path, new { averageRating = 1 })).StatusCode);
    }
    [Theory]
    [InlineData(UserRole.Landlord)] [InlineData(UserRole.Admin)] [InlineData(UserRole.MaintenanceTechnician)]
    public async Task OnlyTenantCanReadOwnOrWrite(UserRole role)
    {
        using var factory = new AuthApiFactory(); using var client = Client(factory, Guid.NewGuid(), role);
        var path = $"/api/viewings/{Guid.NewGuid()}/review";
        Assert.Equal(HttpStatusCode.Forbidden, (await client.GetAsync(path)).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await client.PutAsJsonAsync(path, new { propertyRating = 4, landlordRating = 5 })).StatusCode);
    }
    [Theory]
    [InlineData("{}")]
    [InlineData("{\"propertyRating\":4}")]
    [InlineData("{\"propertyRating\":4.5,\"landlordRating\":5}")]
    [InlineData("{\"propertyRating\":\"4\",\"landlordRating\":5}")]
    [InlineData("{\"propertyRating\":4,\"landlordRating\":\"bad\"}")]
    [InlineData("{\"propertyRating\":0,\"landlordRating\":5}")]
    [InlineData("{\"propertyRating\":4,\"landlordRating\":6}")]
    public async Task InvalidJsonRatingsRejected(string body)
    {
        using var factory = new AuthApiFactory(); using var client = Client(factory, Guid.NewGuid(), UserRole.Tenant);
        Assert.Equal(HttpStatusCode.BadRequest, (await client.PutAsync($"/api/viewings/{Guid.NewGuid()}/review", new StringContent(body, Encoding.UTF8, "application/json"))).StatusCode);
    }
    [Fact]
    public async Task JwtOwnershipAndPrivateOwnContract_PublicAnonymousContractContainsNoReviewerIdentity()
    {
        using var factory = new AuthApiFactory(); var tenant = Guid.NewGuid(); var landlord = Guid.NewGuid();
        factory.EnsureActiveUser(landlord, UserRole.Landlord);
        using var owner = Client(factory, tenant, UserRole.Tenant); using var stranger = Client(factory, Guid.NewGuid(), UserRole.Tenant);
        using var anonymous = factory.CreateHttpsClient();
        var property = new Property { LandlordId = landlord, Title = "Viewed home" };
        var viewing = new ViewingRequest { TenantId = tenant, PropertyId = property.Id, Status = ViewingStatus.Completed };
        using (var scope = factory.Services.CreateScope()) { var db = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>(); db.AddRange(property, viewing); await db.SaveChangesAsync(); }
        var path = $"/api/viewings/{viewing.Id}/review";
        Assert.Equal(HttpStatusCode.Unauthorized, (await anonymous.GetAsync(path)).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await anonymous.PutAsJsonAsync(path, new { propertyRating = 1, landlordRating = 1 })).StatusCode);
        Assert.Equal(HttpStatusCode.NoContent, (await owner.GetAsync(path)).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await stranger.PutAsJsonAsync(path, new { propertyRating = 1, landlordRating = 1, tenantId = tenant })).StatusCode);
        var first = await owner.PutAsJsonAsync(path, new { propertyRating = 1, landlordRating = 5, comment = "  Safe comment  ", tenantId = Guid.NewGuid(), propertyId = Guid.NewGuid(), landlordId = Guid.NewGuid() });
        Assert.Equal(HttpStatusCode.OK, first.StatusCode); var review = (await first.Content.ReadFromJsonAsync<ViewingReviewDto>())!;
        Assert.Equal("Safe comment", review.Comment);
        Assert.Equal(HttpStatusCode.NotFound, (await stranger.GetAsync(path)).StatusCode);
        Assert.Equal(review.Id, (await owner.GetFromJsonAsync<ViewingReviewDto>(path))!.Id);
        var updated = (await (await owner.PutAsJsonAsync(path, new { propertyRating = 5, landlordRating = 2 })).Content.ReadFromJsonAsync<ViewingReviewDto>())!;
        Assert.Equal(review.Id, updated.Id); Assert.Equal(review.CreatedAt, updated.CreatedAt);
        await owner.PutAsJsonAsync(path, new { propertyRating = 4, landlordRating = 5, comment = "Safe public comment" });
        foreach (var endpoint in new[] { "viewing-reviews", "landlord-viewing-reviews" })
        {
            var response = await anonymous.GetAsync($"/api/properties/{property.Id}/{endpoint}"); Assert.Equal(HttpStatusCode.OK, response.StatusCode);
            using var document = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
            Assert.Equal(new[] { "averageRating", "reviewCount", "reviews" }, document.RootElement.EnumerateObject().Select(p => p.Name));
            var comment = document.RootElement.GetProperty("reviews")[0];
            Assert.Equal(new[] { "rating", "comment", "reviewMonth" }, comment.EnumerateObject().Select(p => p.Name));
            Assert.Matches("^\\d{4}-\\d{2}$", comment.GetProperty("reviewMonth").GetString()!);
        }
        using var check = factory.Services.CreateScope(); var stored = await check.ServiceProvider.GetRequiredService<ApplicationDbContext>().ViewingReviews.SingleAsync();
        Assert.Equal(tenant, stored.TenantId); Assert.Equal(property.Id, stored.PropertyId); Assert.Equal(landlord, stored.LandlordId);
    }
    [Fact]
    public async Task FullPropertyFeedbackIsOwnerOnlyAndReturnsAllReviewsWithoutIdentity()
    {
        using var factory = new AuthApiFactory(); var landlord = Guid.NewGuid();
        using var owner = Client(factory, landlord, UserRole.Landlord);
        using var stranger = Client(factory, Guid.NewGuid(), UserRole.Landlord);
        using var tenant = Client(factory, Guid.NewGuid(), UserRole.Tenant);
        using var anonymous = factory.CreateHttpsClient();
        var property = new Property { LandlordId = landlord, Title = "Owned home" };
        using (var scope = factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>(); db.Add(property);
            for (var index = 0; index < 7; index++)
            {
                var viewing = new ViewingRequest { TenantId = Guid.NewGuid(), PropertyId = property.Id, Status = ViewingStatus.Completed };
                db.Add(viewing);
                db.Add(new ViewingReview { ViewingId = viewing.Id, TenantId = viewing.TenantId, PropertyId = property.Id,
                    LandlordId = landlord, PropertyRating = 4, LandlordRating = 5, Comment = index == 0 ? null : $"Feedback {index}",
                    CreatedAt = DateTimeOffset.UtcNow.AddDays(-index), UpdatedAt = DateTimeOffset.UtcNow });
            }
            await db.SaveChangesAsync();
        }
        var path = $"/api/landlord/viewing-reviews/properties/{property.Id}";
        Assert.Equal(HttpStatusCode.Unauthorized, (await anonymous.GetAsync(path)).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await tenant.GetAsync(path)).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await stranger.GetAsync(path)).StatusCode);
        var response = await owner.GetAsync(path); Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        using var document = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        Assert.Equal(7, document.RootElement.GetProperty("reviewCount").GetInt32());
        var reviews = document.RootElement.GetProperty("reviews"); Assert.Equal(7, reviews.GetArrayLength());
        Assert.Equal("", reviews[0].GetProperty("comment").GetString());
        foreach (var review in reviews.EnumerateArray())
            Assert.Equal(new[] { "rating", "comment", "reviewMonth" }, review.EnumerateObject().Select(p => p.Name));
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
