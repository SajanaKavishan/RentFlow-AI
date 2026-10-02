using System.IdentityModel.Tokens.Jwt;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Claims;
using System.Text;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.IdentityModel.Tokens;
using RentFlow.Api.Data;
using RentFlow.Api.DTOs.Viewings;
using RentFlow.Api.Models;
using RentFlow.Api.Tests.Services;
using Xunit;

namespace RentFlow.Api.Tests.Authentication;

public sealed class ViewingAvailabilityEndpointsTests
{
    private static HttpClient Client(AuthApiFactory factory, Guid id, UserRole role)
    {
        factory.EnsureActiveUser(id, role);
        var client = factory.CreateHttpsClient();
        var token = new JwtSecurityToken(issuer: "RentFlow.Api.Tests", audience: "RentFlow.TestClients",
            claims: [new Claim(JwtRegisteredClaimNames.Sub, id.ToString()), new Claim("role", role.ToString()), new Claim("token_version", "0")],
            expires: DateTime.UtcNow.AddMinutes(10), signingCredentials: new SigningCredentials(
                new SymmetricSecurityKey(Encoding.UTF8.GetBytes("test-only-signing-key-that-is-at-least-32-bytes-long")), SecurityAlgorithms.HmacSha256));
        client.DefaultRequestHeaders.Authorization = new("Bearer", new JwtSecurityTokenHandler().WriteToken(token));
        return client;
    }
    private static async Task<Property> Seed(AuthApiFactory factory)
    {
        var property = ViewingAvailabilityServiceTests.Property(); factory.EnsureActiveUser(property.LandlordId, UserRole.Landlord);
        using var scope = factory.Services.CreateScope(); var db = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
        db.Add(property); await db.SaveChangesAsync(); return property;
    }

    [Fact]
    public async Task OwnerSavesSchedule_TenantGetsSlotsAndSubmitsPendingBeforeAvailableFrom()
    {
        using var factory = new AuthApiFactory(new ViewingAvailabilityServiceTests.Clock(new(2030, 10, 6, 0, 0, 0, TimeSpan.Zero)));
        var property = await Seed(factory); using var owner = Client(factory, property.LandlordId, UserRole.Landlord);
        using var tenant = Client(factory, Guid.NewGuid(), UserRole.Tenant);
        var route = $"/api/properties/{property.Id}";
        var empty = await owner.GetFromJsonAsync<ViewingAvailabilityDto>($"{route}/viewing-availability"); Assert.Empty(empty!.Windows);
        Assert.Equal(HttpStatusCode.OK, (await owner.PutAsJsonAsync($"{route}/viewing-availability", ViewingAvailabilityServiceTests.Schedule(property.Id))).StatusCode);
        var slots = await tenant.GetFromJsonAsync<ViewingSlotsDto>($"{route}/viewing-slots?date=2030-10-07"); Assert.Equal(8, slots!.Slots.Count);
        var created = await tenant.PostAsJsonAsync("/api/viewings", new CreateViewingRequestDto { PropertyId = property.Id, RequestedDateTime = slots.Slots[0].RequestedDateTime });
        Assert.Equal(HttpStatusCode.Created, created.StatusCode);
        var result = await created.Content.ReadFromJsonAsync<ViewingResponseDto>();
        Assert.Equal(ViewingStatus.Pending, result!.Status); Assert.Equal("9:00 AM", result.RequestedDisplayTime);
        Assert.Equal("Asia/Colombo", result.TimeZoneId);
        using var otherTenant = Client(factory, Guid.NewGuid(), UserRole.Tenant);
        var competingResponse = await otherTenant.PostAsJsonAsync("/api/viewings", new CreateViewingRequestDto
            { PropertyId = property.Id, RequestedDateTime = slots.Slots[0].RequestedDateTime });
        Assert.Equal(HttpStatusCode.Created, competingResponse.StatusCode);
        var competing = await competingResponse.Content.ReadFromJsonAsync<ViewingResponseDto>();
        Assert.Equal(HttpStatusCode.OK, (await owner.PatchAsJsonAsync($"/api/viewings/{result.Id}/approve", new UpdateViewingStatusDto())).StatusCode);
        Assert.Equal(HttpStatusCode.Conflict, (await owner.PatchAsJsonAsync($"/api/viewings/{competing!.Id}/approve", new UpdateViewingStatusDto())).StatusCode);
        Assert.Equal(ViewingStatus.Pending, (await otherTenant.GetFromJsonAsync<ViewingResponseDto>($"/api/viewings/{competing.Id}"))!.Status);
        Assert.Equal(HttpStatusCode.Conflict, (await tenant.PostAsJsonAsync("/api/viewings", new CreateViewingRequestDto { PropertyId = property.Id, RequestedDateTime = slots.Slots[0].RequestedDateTime.AddMinutes(1) })).StatusCode);
    }

    [Theory]
    [InlineData(UserRole.Tenant, HttpStatusCode.Forbidden)]
    [InlineData(UserRole.Landlord, HttpStatusCode.NotFound)]
    [InlineData(UserRole.MaintenanceTechnician, HttpStatusCode.Forbidden)]
    public async Task PrivateConfigurationRequiresOwner(UserRole role, HttpStatusCode expected)
    {
        using var factory = new AuthApiFactory(); var property = await Seed(factory);
        using var client = Client(factory, Guid.NewGuid(), role); var route = $"/api/properties/{property.Id}/viewing-availability";
        Assert.Equal(expected, (await client.GetAsync(route)).StatusCode);
        Assert.Equal(expected, (await client.PutAsJsonAsync(route, ViewingAvailabilityServiceTests.Schedule(property.Id))).StatusCode);
    }

    [Fact]
    public async Task AdminConventionsArePreserved_AndMissingPropertyIsNotFound()
    {
        using var factory = new AuthApiFactory(); var property = await Seed(factory);
        using var admin = Client(factory, Guid.NewGuid(), UserRole.Admin);
        Assert.Equal(HttpStatusCode.OK, (await admin.GetAsync($"/api/properties/{property.Id}/viewing-availability")).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await admin.PutAsJsonAsync($"/api/properties/{property.Id}/viewing-availability", ViewingAvailabilityServiceTests.Schedule(property.Id))).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await admin.GetAsync($"/api/properties/{Guid.NewGuid()}/viewing-availability")).StatusCode);
        using var tenant = Client(factory, Guid.NewGuid(), UserRole.Tenant);
        Assert.Equal(HttpStatusCode.NotFound, (await tenant.GetAsync($"/api/properties/{Guid.NewGuid()}/viewing-slots?date=2030-10-07")).StatusCode);
        using var anonymous = factory.CreateHttpsClient();
        Assert.Equal(HttpStatusCode.Unauthorized, (await anonymous.GetAsync($"/api/properties/{property.Id}/viewing-slots?date=2030-10-07")).StatusCode);
    }

    [Theory]
    [InlineData("2030-02-30")] [InlineData("2030-10-07T09:00:00Z")] [InlineData("bad")]
    public async Task SlotsRejectInvalidCalendarDates(string date)
    {
        using var factory = new AuthApiFactory(); var property = await Seed(factory);
        using var client = Client(factory, Guid.NewGuid(), UserRole.Tenant);
        Assert.Equal(HttpStatusCode.BadRequest, (await client.GetAsync($"/api/properties/{property.Id}/viewing-slots?date={date}")).StatusCode);
        using var owner = Client(factory, property.LandlordId, UserRole.Landlord);
        Assert.Equal(HttpStatusCode.Forbidden, (await owner.GetAsync($"/api/properties/{property.Id}/viewing-slots?date=2030-10-07")).StatusCode);
    }
}
