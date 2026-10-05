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
using RentFlow.Api.DTOs.RentalApplications;
using RentFlow.Api.Models;
using Xunit;

namespace RentFlow.Api.Tests.Authentication;

public sealed class RentalApplicationEligibilityEndpointsTests
{
    private static readonly Guid Tenant = Guid.NewGuid();
    private static readonly Guid OtherTenant = Guid.NewGuid();
    [Theory]
    [InlineData(UserRole.Landlord)]
    [InlineData(UserRole.Admin)]
    [InlineData(UserRole.MaintenanceTechnician)]
    public async Task EligibilityEndpoints_DenyNonTenantRoles(UserRole role)
    {
        using var factory = new AuthApiFactory(); var property = await Seed(factory);
        using var client = Client(factory, Guid.NewGuid(), role);
        Assert.Equal(HttpStatusCode.Forbidden, (await client.GetAsync($"/api/properties/{property.Id}/rental-application-eligibility")).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await client.GetAsync("/api/rental-applications/eligible-properties")).StatusCode);
    }
    [Fact]
    public async Task AnonymousEndpoints_DenyAccess()
    {
        using var factory = new AuthApiFactory(); using var client = factory.CreateHttpsClient();
        Assert.Equal(HttpStatusCode.Unauthorized, (await client.GetAsync($"/api/properties/{Guid.NewGuid()}/rental-application-eligibility")).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await client.GetAsync("/api/rental-applications/eligible-properties")).StatusCode);
    }
    [Fact]
    public async Task JwtIdentity_CannotInheritAnotherTenantsCompletedViewingOrApplication()
    {
        using var factory = new AuthApiFactory(); var property = await Seed(factory);
        using (var scope = factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
            db.Add(new ViewingRequest { PropertyId = property.Id, TenantId = OtherTenant, Status = ViewingStatus.Completed });
            db.Add(new RentalApplication { PropertyId = property.Id, TenantId = OtherTenant, Status = RentalApplicationStatus.Draft });
            await db.SaveChangesAsync();
        }
        using var client = Client(factory, Tenant, UserRole.Tenant);
        var eligibility = await client.GetFromJsonAsync<RentalApplicationEligibilityDto>($"/api/properties/{property.Id}/rental-application-eligibility?tenantId={OtherTenant}");
        Assert.False(eligibility!.CanApply); Assert.False(eligibility.HasCompletedViewing); Assert.Null(eligibility.ExistingApplicationId);
        Assert.Empty((await client.GetFromJsonAsync<List<EligibleApplicationPropertyDto>>("/api/rental-applications/eligible-properties"))!);
        var create = await client.PostAsJsonAsync($"/api/rental-applications?tenantId={OtherTenant}", new
        { propertyId = property.Id, tenantId = OtherTenant, canApply = true, moveInDate = "2030-01-02", monthlyIncome = 5000, occupation = "Engineer", numberOfOccupants = 1 });
        Assert.Equal(HttpStatusCode.Conflict, create.StatusCode);
        var problem = await create.Content.ReadFromJsonAsync<Microsoft.AspNetCore.Mvc.ProblemDetails>();
        Assert.Equal("Complete a viewing for this property before starting a rental application.", problem!.Detail);
    }
    [Fact]
    public async Task EligibleTenant_CanCreateButExistingActiveApplicationReplacesEligibility()
    {
        using var factory = new AuthApiFactory(); var property = await Seed(factory, completed: true);
        using var client = Client(factory, Tenant, UserRole.Tenant);
        var before = await client.GetFromJsonAsync<RentalApplicationEligibilityDto>($"/api/properties/{property.Id}/rental-application-eligibility");
        Assert.True(before!.CanApply);
        var properties = await client.GetFromJsonAsync<List<EligibleApplicationPropertyDto>>("/api/rental-applications/eligible-properties");
        Assert.Equal(property.Id, Assert.Single(properties!).Id);
        var create = await client.PostAsJsonAsync("/api/rental-applications", new
        { propertyId = property.Id, moveInDate = "2030-01-02", monthlyIncome = 5000, occupation = "Engineer", numberOfOccupants = 1 });
        Assert.Equal(HttpStatusCode.Created, create.StatusCode);
        var application = (await create.Content.ReadFromJsonAsync<RentalApplicationResponseDto>())!;
        Assert.Equal(Tenant, application.TenantId);
        var after = (await client.GetFromJsonAsync<RentalApplicationEligibilityDto>($"/api/properties/{property.Id}/rental-application-eligibility"))!;
        Assert.False(after.CanApply); Assert.True(after.HasCompletedViewing); Assert.Equal(application.Id, after.ExistingApplicationId);
        Assert.Empty((await client.GetFromJsonAsync<List<EligibleApplicationPropertyDto>>("/api/rental-applications/eligible-properties"))!);
    }
    [Fact]
    public async Task LegacyDraftSubmission_CannotBypassRequirementAndDraftRemainsAccessible()
    {
        using var factory = new AuthApiFactory(); var property = await Seed(factory);
        var draft = new RentalApplication { TenantId = Tenant, PropertyId = property.Id,
            MoveInDate = new DateOnly(2030, 1, 2), MonthlyIncome = 5000, Occupation = "Engineer", NumberOfOccupants = 1, TenantNote = "Keep data" };
        using (var scope = factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>(); db.Add(draft); await db.SaveChangesAsync();
        }
        using var client = Client(factory, Tenant, UserRole.Tenant);
        var response = await client.PatchAsJsonAsync($"/api/rental-applications/{draft.Id}/submit", new { hasCompletedViewing = true });
        Assert.Equal(HttpStatusCode.Conflict, response.StatusCode);
        var preserved = (await client.GetFromJsonAsync<RentalApplicationResponseDto>($"/api/rental-applications/{draft.Id}"))!;
        Assert.Equal(RentalApplicationStatus.Draft, preserved.Status); Assert.Equal("Keep data", preserved.TenantNote); Assert.Null(preserved.SubmittedAt);
        using var other = Client(factory, OtherTenant, UserRole.Tenant);
        Assert.Equal(HttpStatusCode.NotFound, (await other.PatchAsync($"/api/rental-applications/{draft.Id}/submit", null)).StatusCode);
    }
    private static async Task<Property> Seed(AuthApiFactory factory, bool completed = false)
    {
        factory.EnsureActiveUser(Tenant, UserRole.Tenant); factory.EnsureActiveUser(OtherTenant, UserRole.Tenant);
        using var scope = factory.Services.CreateScope(); var db = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
        var property = new Property { LandlordId = Guid.NewGuid(), Title = "Viewed home", Address = "Test", City = "Colombo" };
        db.Add(property);
        if (completed) db.AddRange(new ViewingRequest { PropertyId = property.Id, TenantId = Tenant, Status = ViewingStatus.Completed }, new ViewingRequest { PropertyId = property.Id, TenantId = Tenant, Status = ViewingStatus.Completed });
        await db.SaveChangesAsync(); return property;
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
