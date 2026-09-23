using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using RentFlow.Api.Data;
using RentFlow.Api.DTOs.Maintenance;
using RentFlow.Api.Models;
using RentFlow.Api.Services;
using RentFlow.Api.Tests.Authentication;
using Xunit;

namespace RentFlow.Api.Tests.Controllers;

public sealed class MaintenanceRequestsAuthorizationTests
{
    private const string ValidPassword = "Secure1!Password";

    [Fact]
    public async Task GetById_WithoutToken_ReturnsUnauthorized()
    {
        using var factory = new AuthApiFactory();
        using var client = factory.CreateHttpsClient();

        var response = await client.GetAsync($"/api/maintenance-requests/{Guid.NewGuid()}");

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task Create_WithWrongRole_ReturnsForbidden()
    {
        using var factory = new AuthApiFactory();
        using var client = factory.CreateHttpsClient();
        await AuthenticateAsync(client, "landlord-create@example.com", UserRole.Landlord);

        var response = await client.PostAsJsonAsync(
            "/api/maintenance-requests",
            CreateRequest());

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Fact]
    public async Task Create_UsesAuthenticatedTenantIdentity()
    {
        using var factory = new AuthApiFactory();
        using var client = factory.CreateHttpsClient();
        var tenantId = await AuthenticateAsync(client, "tenant-create@example.com", UserRole.Tenant);

        var response = await client.PostAsJsonAsync(
            "/api/maintenance-requests",
            CreateRequest());

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        var body = await ParseAsync(response);
        Assert.Equal(tenantId, body.RootElement.GetProperty("tenantId").GetGuid());
    }

    [Fact]
    public async Task Create_WithAnotherTenantQueryId_ReturnsForbidden()
    {
        using var factory = new AuthApiFactory();
        using var client = factory.CreateHttpsClient();
        await AuthenticateAsync(client, "tenant-spoof@example.com", UserRole.Tenant);

        var response = await client.PostAsJsonAsync(
            $"/api/maintenance-requests?tenantId={Guid.NewGuid()}",
            CreateRequest());

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Fact]
    public async Task GetById_ForAnotherTenantRequest_ReturnsNotFound()
    {
        using var factory = new AuthApiFactory();
        using var client = factory.CreateHttpsClient();
        await AuthenticateAsync(client, "tenant-idor@example.com", UserRole.Tenant);
        var requestId = await SeedRequestAsync(factory, tenantId: Guid.NewGuid());

        var response = await client.GetAsync($"/api/maintenance-requests/{requestId}");

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    [Fact]
    public async Task SubmitEstimate_WithTenantRole_ReturnsForbidden()
    {
        using var factory = new AuthApiFactory();
        using var client = factory.CreateHttpsClient();
        await AuthenticateAsync(client, "tenant-estimate@example.com", UserRole.Tenant);

        var response = await client.PostAsJsonAsync(
            $"/api/maintenance-requests/{Guid.NewGuid()}/estimates",
            new SubmitRepairEstimateDto { LaborCost = 25m });

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Fact]
    public async Task SubmitEstimate_UsesAuthenticatedTechnicianIdentity()
    {
        using var factory = new AuthApiFactory();
        using var client = factory.CreateHttpsClient();
        var technicianId = await AuthenticateAsync(
            client,
            "technician-submit@example.com",
            UserRole.MaintenanceTechnician,
            factory);
        var requestId = await SeedRequestAsync(
            factory,
            status: MaintenanceRequestStatus.EstimatePending,
            technicianId: technicianId);

        var response = await client.PostAsJsonAsync(
            $"/api/maintenance-requests/{requestId}/estimates",
            new SubmitRepairEstimateDto { LaborCost = 25m, PartsCost = 10m });

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        var body = await ParseAsync(response);
        Assert.Equal(technicianId, body.RootElement.GetProperty("technicianId").GetGuid());
    }

    [Fact]
    public async Task Triage_WithTenantRole_ReturnsForbidden()
    {
        using var factory = new AuthApiFactory();
        using var client = factory.CreateHttpsClient();
        await AuthenticateAsync(client, "tenant-triage@example.com", UserRole.Tenant);

        var response = await client.PatchAsJsonAsync(
            $"/api/maintenance-requests/{Guid.NewGuid()}/triage",
            new TriageMaintenanceRequestDto
            {
                Category = MaintenanceCategory.Plumbing,
                Priority = MaintenancePriority.High
            });

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Fact]
    public async Task ApproveEstimate_UsesAuthenticatedLandlordIdentity()
    {
        using var factory = new AuthApiFactory();
        using var client = factory.CreateHttpsClient();
        var landlordId = await AuthenticateAsync(client, "landlord-approve@example.com", UserRole.Landlord);
        var estimate = await SeedSubmittedEstimateAsync(factory);

        var response = await client.PatchAsJsonAsync(
            $"/api/maintenance-requests/{estimate.RequestId}/estimates/{estimate.EstimateId}/approve",
            new ReviewRepairEstimateDto { ReviewNotes = "Approved." });

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        using var scope = factory.Services.CreateScope();
        var dbContext = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
        var stored = await dbContext.RepairEstimates.SingleAsync(item => item.Id == estimate.EstimateId);
        Assert.Equal(landlordId, stored.ReviewedByUserId);
    }

    private static async Task<Guid> AuthenticateAsync(
        HttpClient client,
        string email,
        UserRole role,
        AuthApiFactory? factory = null)
    {
        HttpResponseMessage response;
        if (role is UserRole.Tenant or UserRole.Landlord)
        {
            response = await client.PostAsJsonAsync("/api/auth/register", new
            {
                fullName = "Maintenance Auth User",
                email,
                phoneNumber = "+94770000000",
                password = ValidPassword,
                role = role.ToString()
            });
        }
        else
        {
            if (factory is null)
            {
                throw new InvalidOperationException("A factory is required to seed privileged users.");
            }

            await SeedUserAsync(factory, email, role);
            response = await client.PostAsJsonAsync("/api/auth/login", new { email, password = ValidPassword });
        }

        Assert.True(response.IsSuccessStatusCode, await response.Content.ReadAsStringAsync());
        var body = await ParseAsync(response);
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue(
            "Bearer",
            body.RootElement.GetProperty("accessToken").GetString());
        return body.RootElement.GetProperty("user").GetProperty("id").GetGuid();
    }

    private static async Task SeedUserAsync(AuthApiFactory factory, string email, UserRole role)
    {
        using var scope = factory.Services.CreateScope();
        var services = scope.ServiceProvider;
        var user = new ApplicationUser
        {
            Id = Guid.NewGuid(),
            FullName = "Maintenance Technician",
            Email = email,
            NormalizedEmail = AuthService.NormalizeEmail(email),
            PhoneNumber = "+94770000000",
            Role = role,
            IsActive = true,
            CreatedAt = DateTimeOffset.UtcNow,
            UpdatedAt = DateTimeOffset.UtcNow
        };
        user.PasswordHash = services
            .GetRequiredService<IPasswordHasher<ApplicationUser>>()
            .HashPassword(user, ValidPassword);
        services.GetRequiredService<ApplicationDbContext>().Users.Add(user);
        await services.GetRequiredService<ApplicationDbContext>().SaveChangesAsync();
    }

    private static async Task<Guid> SeedRequestAsync(
        AuthApiFactory factory,
        Guid? tenantId = null,
        MaintenanceRequestStatus status = MaintenanceRequestStatus.Submitted,
        Guid? technicianId = null)
    {
        using var scope = factory.Services.CreateScope();
        var dbContext = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
        var request = new MaintenanceRequest
        {
            Id = Guid.NewGuid(),
            TenantId = tenantId ?? Guid.NewGuid(),
            PropertyId = Guid.NewGuid(),
            TechnicianId = technicianId,
            Title = "Leak",
            Description = "Kitchen tap leak",
            Category = MaintenanceCategory.Plumbing,
            Priority = MaintenancePriority.Normal,
            Status = status,
            CreatedAt = DateTimeOffset.UtcNow
        };
        dbContext.MaintenanceRequests.Add(request);
        await dbContext.SaveChangesAsync();
        return request.Id;
    }

    private static async Task<(Guid RequestId, Guid EstimateId)> SeedSubmittedEstimateAsync(
        AuthApiFactory factory)
    {
        using var scope = factory.Services.CreateScope();
        var dbContext = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
        var request = new MaintenanceRequest
        {
            Id = Guid.NewGuid(),
            TenantId = Guid.NewGuid(),
            PropertyId = Guid.NewGuid(),
            TechnicianId = Guid.NewGuid(),
            Title = "Estimate review",
            Description = "Review the estimate",
            Category = MaintenanceCategory.Electrical,
            Priority = MaintenancePriority.Normal,
            Status = MaintenanceRequestStatus.AwaitingLandlordApproval,
            CreatedAt = DateTimeOffset.UtcNow
        };
        var estimate = new RepairEstimate
        {
            Id = Guid.NewGuid(),
            MaintenanceRequestId = request.Id,
            TechnicianId = request.TechnicianId!.Value,
            VersionNumber = 1,
            LaborCost = 25m,
            PartsCost = 10m,
            AdditionalCost = 0m,
            TotalCost = 35m,
            Status = RepairEstimateStatus.Submitted,
            CreatedAt = DateTimeOffset.UtcNow,
            SubmittedAt = DateTimeOffset.UtcNow
        };
        dbContext.MaintenanceRequests.Add(request);
        dbContext.RepairEstimates.Add(estimate);
        await dbContext.SaveChangesAsync();
        return (request.Id, estimate.Id);
    }

    private static CreateMaintenanceRequestDto CreateRequest() => new()
    {
        PropertyId = Guid.NewGuid(),
        Title = "Leak",
        Description = "Kitchen tap leak",
        Category = MaintenanceCategory.Plumbing,
        Priority = MaintenancePriority.Normal
    };

    private static async Task<JsonDocument> ParseAsync(HttpResponseMessage response) =>
        JsonDocument.Parse(await response.Content.ReadAsStringAsync());
}
