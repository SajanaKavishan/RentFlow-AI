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
using RentFlow.Api.DTOs.Viewings;
using RentFlow.Api.Models;
using RentFlow.Api.Tests.Services;
using Xunit;

namespace RentFlow.Api.Tests.Authentication;

public sealed class ViewingCompletionEndpointsTests
{
    private static readonly Guid LandlordId = Guid.NewGuid();
    private static readonly Guid TenantId = Guid.NewGuid();
    private static readonly DateTimeOffset Start = new(2030, 1, 2, 4, 30, 0, TimeSpan.Zero);

    [Theory]
    [InlineData(15, -1, HttpStatusCode.Conflict)]
    [InlineData(15, 0, HttpStatusCode.OK)]
    [InlineData(120, -1, HttpStatusCode.Conflict)]
    [InlineData(120, 0, HttpStatusCode.OK)]
    [InlineData(120, 1, HttpStatusCode.OK)]
    public async Task Owner_ContractAndActionUseSameEndBoundary(int duration, long ticksAfterEnd, HttpStatusCode expected)
    {
        var end = Start.AddMinutes(duration);
        var clock = new ViewingCancellationTests.Clock(end.AddTicks(ticksAfterEnd));
        using var factory = new AuthApiFactory(clock);
        var viewing = await Seed(factory, duration: duration);
        using var client = Client(factory, LandlordId, UserRole.Landlord);
        var detail = (await client.GetFromJsonAsync<ViewingResponseDto>($"/api/viewings/{viewing.Id}"))!;
        var list = Assert.Single((await client.GetFromJsonAsync<List<ViewingResponseDto>>($"/api/viewings/property/{viewing.PropertyId}"))!);
        Assert.Equal(expected == HttpStatusCode.OK, detail.CanMarkCompleted);
        Assert.Equal(detail.CanMarkCompleted, list.CanMarkCompleted);
        Assert.Equal(end, detail.CompletionEligibleAt);
        Assert.Equal(end, list.CompletionEligibleAt);
        Assert.Null(list.Tenant.PhoneNumber);
        Assert.Equal(ViewingStatus.Approved, detail.Status);
        // Client-supplied actor, clock, duration and status are never authoritative.
        using var response = await client.PatchAsJsonAsync($"/api/viewings/{viewing.Id}/complete", new
        {
            landlordId = Guid.NewGuid(), status = ViewingStatus.Pending, durationMinutes = 0,
            serverNow = end.AddDays(1), canMarkCompleted = true
        });
        Assert.Equal(expected, response.StatusCode);
        if (expected == HttpStatusCode.OK)
        {
            var result = (await response.Content.ReadFromJsonAsync<ViewingResponseDto>())!;
            Assert.Equal(ViewingStatus.Completed, result.Status);
            Assert.Equal(clock.Now, result.UpdatedAt);
            Assert.Equal(Start, result.RequestedDateTime);
            Assert.Equal(duration, result.DurationMinutes);
            Assert.Equal(TenantId, result.TenantId);
            Assert.Equal(viewing.PropertyId, result.PropertyId);
            Assert.False(result.CanMarkCompleted);
            Assert.Null(result.CompletionEligibleAt);
            Assert.Null(result.Tenant.PhoneNumber);
            using var repeat = await client.PatchAsync($"/api/viewings/{viewing.Id}/complete", null);
            Assert.Equal(HttpStatusCode.Conflict, repeat.StatusCode);
            var refreshed = (await client.GetFromJsonAsync<ViewingResponseDto>($"/api/viewings/{viewing.Id}"))!;
            Assert.Equal(result.Status, refreshed.Status);
            Assert.Equal(result.UpdatedAt, refreshed.UpdatedAt);
        }
        else
        {
            var problem = (await response.Content.ReadFromJsonAsync<Microsoft.AspNetCore.Mvc.ProblemDetails>())!;
            Assert.Equal(409, problem.Status);
            Assert.Equal("Viewing request conflict.", problem.Title);
            Assert.Equal("This viewing can only be marked completed after the scheduled viewing has ended.", problem.Detail);
        }
    }

    [Theory]
    [InlineData(UserRole.Tenant, HttpStatusCode.Forbidden)]
    [InlineData(UserRole.MaintenanceTechnician, HttpStatusCode.Forbidden)]
    [InlineData(UserRole.Landlord, HttpStatusCode.NotFound)]
    public async Task UnauthorizedActors_CannotCompleteEvenWithForgedOwner(UserRole role, HttpStatusCode expected)
    {
        using var factory = new AuthApiFactory(new ViewingCancellationTests.Clock(Start.AddDays(1)));
        var viewing = await Seed(factory);
        using var client = Client(factory, role == UserRole.Tenant ? TenantId : Guid.NewGuid(), role);
        using var response = await client.PatchAsJsonAsync($"/api/viewings/{viewing.Id}/complete?landlordId={LandlordId}",
            new { landlordId = LandlordId, canMarkCompleted = true });
        Assert.Equal(expected, response.StatusCode);
        using var scope = factory.Services.CreateScope();
        var stored = await scope.ServiceProvider.GetRequiredService<ApplicationDbContext>().ViewingRequests.SingleAsync();
        Assert.Equal(ViewingStatus.Approved, stored.Status);
        Assert.Null(stored.UpdatedAt);
        if (role == UserRole.Tenant)
        {
            var detail = (await client.GetFromJsonAsync<ViewingResponseDto>($"/api/viewings/{viewing.Id}"))!;
            var list = Assert.Single((await client.GetFromJsonAsync<List<ViewingResponseDto>>("/api/viewings"))!);
            Assert.False(detail.CanMarkCompleted);
            Assert.False(list.CanMarkCompleted);
            Assert.Null(detail.Tenant.PhoneNumber);
            Assert.Null(list.Tenant.PhoneNumber);
        }
    }

    [Fact]
    public async Task Anonymous_CannotComplete()
    {
        using var factory = new AuthApiFactory(new ViewingCancellationTests.Clock(Start.AddDays(1)));
        var viewing = await Seed(factory);
        using var client = factory.CreateHttpsClient();
        using var response = await client.PatchAsync($"/api/viewings/{viewing.Id}/complete", null);
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task Admin_PreservesExistingApproveRejectStatusActionPolicyWithoutPhoneDisclosure()
    {
        using var factory = new AuthApiFactory(new ViewingCancellationTests.Clock(Start.AddDays(1)));
        var viewing = await Seed(factory);
        using var client = Client(factory, Guid.NewGuid(), UserRole.Admin);
        var detail = (await client.GetFromJsonAsync<ViewingResponseDto>($"/api/viewings/{viewing.Id}"))!;
        Assert.True(detail.CanMarkCompleted);
        Assert.Null(detail.Tenant.PhoneNumber);
        using var response = await client.PatchAsync($"/api/viewings/{viewing.Id}/complete", null);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal(ViewingStatus.Completed, (await response.Content.ReadFromJsonAsync<ViewingResponseDto>())!.Status);
    }

    [Theory]
    [InlineData(ViewingStatus.Pending)]
    [InlineData(ViewingStatus.Rejected)]
    [InlineData(ViewingStatus.Cancelled)]
    [InlineData(ViewingStatus.Completed)]
    public async Task NonApprovedStatus_UsesExistingConflictProblem(ViewingStatus status)
    {
        using var factory = new AuthApiFactory(new ViewingCancellationTests.Clock(Start.AddDays(1)));
        var viewing = await Seed(factory, status);
        using var client = Client(factory, LandlordId, UserRole.Landlord);
        var detail = (await client.GetFromJsonAsync<ViewingResponseDto>($"/api/viewings/{viewing.Id}"))!;
        Assert.False(detail.CanMarkCompleted);
        Assert.Null(detail.CompletionEligibleAt);
        using var response = await client.PatchAsync($"/api/viewings/{viewing.Id}/complete", null);
        Assert.Equal(HttpStatusCode.Conflict, response.StatusCode);
    }

    [Fact]
    public async Task MissingViewing_ReturnsNotFound()
    {
        using var factory = new AuthApiFactory();
        using var client = Client(factory, LandlordId, UserRole.Landlord);
        using var response = await client.PatchAsync($"/api/viewings/{Guid.NewGuid()}/complete", null);
        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
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

    private static async Task<ViewingRequest> Seed(AuthApiFactory factory,
        ViewingStatus status = ViewingStatus.Approved, int duration = 60)
    {
        factory.EnsureActiveUser(LandlordId, UserRole.Landlord);
        factory.EnsureActiveUser(TenantId, UserRole.Tenant);
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
        var property = new Property
        {
            LandlordId = LandlordId, Title = "Viewing home", Description = "Test",
            Address = "Test Street", City = "Colombo", ViewingTimeZoneId = "Asia/Colombo"
        };
        var viewing = new ViewingRequest
        {
            PropertyId = property.Id, TenantId = TenantId, RequestedDateTime = Start,
            DurationMinutes = duration, Status = status, CreatedAt = Start.AddDays(-1)
        };
        db.AddRange(property, viewing);
        await db.SaveChangesAsync();
        return viewing;
    }
}
