using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using RentFlow.Api.Data;
using RentFlow.Api.Models;
using RentFlow.Api.Services;
using RentFlow.Api.Tests.Authentication;
using Xunit;

namespace RentFlow.Api.Tests.Controllers;

public sealed class MaintenanceTriageValidationTests
{
    [Theory]
    [InlineData("{\"priority\":2}")]
    [InlineData("{\"category\":1}")]
    [InlineData("{}")]
    [InlineData("{\"category\":null,\"priority\":2}")]
    [InlineData("{\"category\":1,\"priority\":null}")]
    [InlineData("{\"category\":999,\"priority\":2}")]
    [InlineData("{\"category\":1,\"priority\":999}")]
    [InlineData("{\"category\":\"invalid\",\"priority\":2}")]
    public async Task InvalidOrMissingFields_Return400WithoutChangingRequest(string payload)
    {
        using var factory = new AuthApiFactory();
        using var client = factory.CreateHttpsClient();
        var original = await SeedAsync(factory, client, UserRole.Landlord);
        using var response = await client.PatchAsync($"/api/maintenance-requests/{original.Id}/triage",
            new StringContent(payload, Encoding.UTF8, "application/json"));
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        using var problem = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        Assert.Equal(400, problem.RootElement.GetProperty("status").GetInt32());
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
        var stored = await db.MaintenanceRequests.SingleAsync(request => request.Id == original.Id);
        Assert.Equal(original.PropertyId, stored.PropertyId);
        Assert.Equal(MaintenanceCategory.Security, stored.Category);
        Assert.Equal(MaintenancePriority.High, stored.Priority);
        Assert.Equal(MaintenanceRequestStatus.Submitted, stored.Status);
        Assert.Null(stored.TriageNotes);
        Assert.Null(stored.UpdatedAt);
        Assert.Empty(db.MaintenanceStatusHistories);
        Assert.Empty(db.Notifications);
    }

    [Theory]
    [InlineData(UserRole.Landlord, MaintenanceCategory.Plumbing, MaintenancePriority.Low)]
    [InlineData(UserRole.Admin, MaintenanceCategory.Plumbing, MaintenancePriority.Low)]
    [InlineData(UserRole.Landlord, MaintenanceCategory.Electrical, MaintenancePriority.Emergency)]
    [InlineData(UserRole.Admin, MaintenanceCategory.Electrical, MaintenancePriority.Normal)]
    public async Task ExplicitValidValues_TriageAndAssignmentPreservePropertyAndDecisions(
        UserRole role, MaintenanceCategory category, MaintenancePriority priority)
    {
        using var factory = new AuthApiFactory();
        using var client = factory.CreateHttpsClient();
        var original = await SeedAsync(factory, client, role);
        using var response = await client.PatchAsJsonAsync($"/api/maintenance-requests/{original.Id}/triage",
            new { category, priority, triageNotes = "Human review", propertyId = Guid.NewGuid() });
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        Assert.Equal((int)category, body.RootElement.GetProperty("category").GetInt32());
        Assert.Equal((int)priority, body.RootElement.GetProperty("priority").GetInt32());
        Assert.Equal(original.PropertyId, body.RootElement.GetProperty("propertyId").GetGuid());
        using var repeated = await client.PatchAsJsonAsync($"/api/maintenance-requests/{original.Id}/triage", new { category, priority });
        Assert.Equal(HttpStatusCode.Conflict, repeated.StatusCode);

        var technician = new ApplicationUser { Id = Guid.NewGuid(), FullName = "Technician", Role = UserRole.MaintenanceTechnician, IsActive = true };
        using (var scope = factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
            var triaged = await db.MaintenanceRequests.SingleAsync(request => request.Id == original.Id);
            Assert.Equal(MaintenanceRequestStatus.Triaged, triaged.Status);
            Assert.Equal(category, triaged.Category);
            Assert.Equal(priority, triaged.Priority);
            Assert.Equal("Human review", triaged.TriageNotes);
            db.Users.Add(technician);
            await db.SaveChangesAsync();
        }
        using var assigned = await client.PatchAsJsonAsync($"/api/maintenance-requests/{original.Id}/assign-technician",
            new { technicianId = technician.Id, propertyId = Guid.NewGuid(), category = MaintenanceCategory.Other, priority = MaintenancePriority.High });
        Assert.Equal(HttpStatusCode.OK, assigned.StatusCode);
        using var finalScope = factory.Services.CreateScope();
        var stored = await finalScope.ServiceProvider.GetRequiredService<ApplicationDbContext>().MaintenanceRequests.SingleAsync(request => request.Id == original.Id);
        Assert.Equal(MaintenanceRequestStatus.Assigned, stored.Status);
        Assert.Equal(technician.Id, stored.TechnicianId);
        Assert.Equal(original.PropertyId, stored.PropertyId);
        Assert.Equal(category, stored.Category);
        Assert.Equal(priority, stored.Priority);
    }

    private static async Task<MaintenanceRequest> SeedAsync(AuthApiFactory factory, HttpClient client, UserRole role)
    {
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
        const string password = "Secure1!Password";
        var actor = new ApplicationUser { Id = Guid.NewGuid(), FullName = "Manager", Email = "manager@example.test",
            NormalizedEmail = AuthService.NormalizeEmail("manager@example.test"), PhoneNumber = "+94770000000", Role = role, IsActive = true };
        actor.PasswordHash = scope.ServiceProvider.GetRequiredService<IPasswordHasher<ApplicationUser>>().HashPassword(actor, password);
        var property = new Property { LandlordId = actor.Id, Title = "Test property", Address = "Test address", City = "Test city" };
        var request = new MaintenanceRequest { PropertyId = property.Id, TenantId = Guid.NewGuid(), Title = "Repair lock", Description = "Broken lock",
            Category = MaintenanceCategory.Security, Priority = MaintenancePriority.High, Status = MaintenanceRequestStatus.Submitted };
        db.AddRange(actor, property, request);
        await db.SaveChangesAsync();
        using var login = await client.PostAsJsonAsync("/api/auth/login", new { email = actor.Email, password });
        Assert.Equal(HttpStatusCode.OK, login.StatusCode);
        using var body = JsonDocument.Parse(await login.Content.ReadAsStringAsync());
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", body.RootElement.GetProperty("accessToken").GetString());
        return request;
    }
}
