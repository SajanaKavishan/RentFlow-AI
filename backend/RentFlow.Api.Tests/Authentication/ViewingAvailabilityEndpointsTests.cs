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
    public async Task ApprovedCancellation_EnforcesDeadlineAndRetainsAuthorization()
    {
        var start = new DateTimeOffset(2030, 10, 7, 4, 30, 0, TimeSpan.Zero);
        var clock = new ViewingCancellationTests.Clock(start.AddHours(-5));
        using var factory = new AuthApiFactory(clock);
        var property = await Seed(factory);
        var tenantId = Guid.NewGuid();
        using var tenant = Client(factory, tenantId, UserRole.Tenant);
        using var otherTenant = Client(factory, Guid.NewGuid(), UserRole.Tenant);
        using var landlord = Client(factory, property.LandlordId, UserRole.Landlord);
        using var otherLandlord = Client(factory, Guid.NewGuid(), UserRole.Landlord);
        var viewing = new ViewingRequest
        {
            TenantId = tenantId, PropertyId = property.Id, RequestedDateTime = start,
            Status = ViewingStatus.Approved, DurationMinutes = 60, CreatedAt = start.AddDays(-1)
        };
        using (var scope = factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
            db.Add(viewing);
            await db.SaveChangesAsync();
        }
        var route = $"/api/viewings/{viewing.Id}";
        Assert.True((await tenant.GetFromJsonAsync<ViewingResponseDto>(route))!.CanCancel);
        Assert.Equal(HttpStatusCode.NotFound, (await otherTenant.GetAsync(route)).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await otherTenant.PatchAsync($"{route}/cancel", null)).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await landlord.PatchAsync($"{route}/cancel", null)).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await otherLandlord.GetAsync(route)).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await landlord.GetAsync(route)).StatusCode);

        clock.Now = clock.Now.AddTicks(1);
        var rejected = await tenant.PatchAsync($"{route}/cancel", null);
        Assert.Equal(HttpStatusCode.Conflict, rejected.StatusCode);
        var problem = await rejected.Content.ReadFromJsonAsync<Microsoft.AspNetCore.Mvc.ProblemDetails>();
        Assert.Equal(409, problem!.Status);
        Assert.Contains("cancellation window has closed", problem.Detail!);
        var refreshed = await tenant.GetFromJsonAsync<ViewingResponseDto>(route);
        Assert.False(refreshed!.CanCancel);
        Assert.Equal(ViewingStatus.Approved, refreshed.Status);

        clock.Now = start.AddHours(-5);
        var allowed = await tenant.PatchAsync($"{route}/cancel", null);
        Assert.Equal(HttpStatusCode.OK, allowed.StatusCode);
        var cancelled = await allowed.Content.ReadFromJsonAsync<ViewingResponseDto>();
        Assert.Equal(ViewingStatus.Cancelled, cancelled!.Status);
        Assert.False(cancelled.CanCancel);
        Assert.Null(cancelled.CancellationDeadline);
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
        var created = await tenant.PostAsJsonAsync("/api/viewings", new CreateViewingRequestDto { TenantMessage = "Please arrange a visit.", PropertyId = property.Id, RequestedDateTime = slots.Slots[0].RequestedDateTime });
        Assert.Equal(HttpStatusCode.Created, created.StatusCode);
        var result = await created.Content.ReadFromJsonAsync<ViewingResponseDto>();
        Assert.Equal(ViewingStatus.Pending, result!.Status); Assert.Equal("9:00 AM", result.RequestedDisplayTime);
        Assert.Equal("Asia/Colombo", result.TimeZoneId);
        using var otherTenant = Client(factory, Guid.NewGuid(), UserRole.Tenant);
        var competingResponse = await otherTenant.PostAsJsonAsync("/api/viewings", new CreateViewingRequestDto
            { TenantMessage = "Please arrange a visit.", PropertyId = property.Id, RequestedDateTime = slots.Slots[0].RequestedDateTime });
        Assert.Equal(HttpStatusCode.Created, competingResponse.StatusCode);
        var competing = await competingResponse.Content.ReadFromJsonAsync<ViewingResponseDto>();
        Assert.Equal(HttpStatusCode.OK, (await owner.PatchAsJsonAsync($"/api/viewings/{result.Id}/approve", new UpdateViewingStatusDto())).StatusCode);
        Assert.Equal(HttpStatusCode.Conflict, (await owner.PatchAsJsonAsync($"/api/viewings/{competing!.Id}/approve", new UpdateViewingStatusDto())).StatusCode);
        Assert.Equal(ViewingStatus.Pending, (await otherTenant.GetFromJsonAsync<ViewingResponseDto>($"/api/viewings/{competing.Id}"))!.Status);
        var enriched = await tenant.GetFromJsonAsync<ViewingSlotsDto>($"{route}/viewing-slots?date=2030-10-07&includeUnavailable=true");
        Assert.Equal(8, enriched!.Slots.Count);
        Assert.False(enriched.Slots[0].IsAvailable);
        Assert.Equal("ApprovedViewing", enriched.Slots[0].UnavailableReason);
        var compatible = await tenant.GetFromJsonAsync<ViewingSlotsDto>($"{route}/viewing-slots?date=2030-10-07");
        Assert.Equal(7, compatible!.Slots.Count);
        Assert.All(compatible.Slots, slot => Assert.True(slot.IsAvailable));
        Assert.Equal(HttpStatusCode.Conflict, (await otherTenant.PostAsJsonAsync("/api/viewings", new CreateViewingRequestDto
            { PropertyId = property.Id, RequestedDateTime = enriched.Slots[0].RequestedDateTime, TenantMessage = "Another visit" })).StatusCode);
        Assert.Equal(HttpStatusCode.Conflict, (await tenant.PostAsJsonAsync("/api/viewings", new CreateViewingRequestDto { TenantMessage = "Please arrange a visit.", PropertyId = property.Id, RequestedDateTime = slots.Slots[0].RequestedDateTime.AddMinutes(1) })).StatusCode);
    }

    [Theory]
    [InlineData(null)] [InlineData("")] [InlineData("  \t\r\n ")]
    public async Task RequiredNote_BlankInputsReturnControlled400WithoutPersisting(string? note)
    {
        using var factory = new AuthApiFactory(new ViewingAvailabilityServiceTests.Clock(new(2030, 10, 6, 0, 0, 0, TimeSpan.Zero)));
        var property = await Seed(factory);
        using var owner = Client(factory, property.LandlordId, UserRole.Landlord);
        using var tenant = Client(factory, Guid.NewGuid(), UserRole.Tenant);
        await owner.PutAsJsonAsync($"/api/properties/{property.Id}/viewing-availability", ViewingAvailabilityServiceTests.Schedule(property.Id));
        var response = await tenant.PostAsJsonAsync("/api/viewings", new CreateViewingRequestDto
        { PropertyId = property.Id, RequestedDateTime = new(2030, 10, 7, 3, 30, 0, TimeSpan.Zero), TenantMessage = note });
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.Contains("note", await response.Content.ReadAsStringAsync(), StringComparison.OrdinalIgnoreCase);
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
        Assert.Empty(db.ViewingRequests); Assert.Empty(db.Notifications);
    }

    [Theory]
    [InlineData(1, HttpStatusCode.Created)]
    [InlineData(500, HttpStatusCode.Created)]
    [InlineData(501, HttpStatusCode.BadRequest)]
    public async Task RequiredNote_EnforcesTrimmedLengthAndAuthenticatedIdentity(int length, HttpStatusCode expected)
    {
        using var factory = new AuthApiFactory(new ViewingAvailabilityServiceTests.Clock(new(2030, 10, 6, 0, 0, 0, TimeSpan.Zero)));
        var property = await Seed(factory); var tenantId = Guid.NewGuid();
        using var owner = Client(factory, property.LandlordId, UserRole.Landlord);
        using var tenant = Client(factory, tenantId, UserRole.Tenant);
        await owner.PutAsJsonAsync($"/api/properties/{property.Id}/viewing-availability", ViewingAvailabilityServiceTests.Schedule(property.Id));
        var response = await tenant.PostAsJsonAsync($"/api/viewings?tenantId={Guid.NewGuid()}", new CreateViewingRequestDto
        { PropertyId = property.Id, RequestedDateTime = new(2030, 10, 7, 3, 30, 0, TimeSpan.Zero), TenantMessage = "  " + new string('x', length) + "  " });
        Assert.Equal(expected, response.StatusCode);
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
        if (expected == HttpStatusCode.Created)
        {
            var created = await response.Content.ReadFromJsonAsync<ViewingResponseDto>();
            Assert.Equal(new string('x', length), created!.TenantMessage);
            Assert.Equal(tenantId, created.TenantId);
            Assert.Equal(new string('x', length), Assert.Single(db.ViewingRequests).TenantMessage);
        }
        else { Assert.Empty(db.ViewingRequests); Assert.Empty(db.Notifications); }
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
