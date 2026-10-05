using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.EntityFrameworkCore.Migrations.Operations;
using Microsoft.Extensions.DependencyInjection;
using RentFlow.Api.Data;
using RentFlow.Api.Data.Migrations;
using RentFlow.Api.Models;
using RentFlow.Api.Services.Interfaces;
using Xunit;

namespace RentFlow.Api.Tests.Authentication;

public sealed class TechnicianMaintenanceContactTests
{
    private const string PrivatePhone = "+94112223344";
    private const string WorkPhone = "+94 77 123 4567";

    [Fact]
    public void Migration_DefaultsNeverCopyPrivatePhone()
    {
        var user = new ApplicationUser { PhoneNumber = PrivatePhone };
        Assert.False(user.MaintenanceContactEnabled);
        Assert.Null(user.MaintenanceContactPhone);
        var operations = new AddTechnicianMaintenanceWorkContact().UpOperations;
        Assert.Equal(2, operations.Count);
        var columns = operations.Cast<AddColumnOperation>().ToArray();
        Assert.All(columns, column => Assert.Equal("Users", column.Table));
        var phone = columns.Single(column => column.Name == "MaintenanceContactPhone");
        Assert.True(phone.IsNullable);
        Assert.Null(phone.DefaultValue);
        Assert.Equal(32, phone.MaxLength);
        Assert.Equal(false, columns.Single(column => column.Name == "MaintenanceContactEnabled").DefaultValue);
    }

    [Theory]
    [InlineData(true, WorkPhone, true, true, WorkPhone)]
    [InlineData(true, "  +94 77 123 4567  ", true, true, WorkPhone)]
    [InlineData(false, WorkPhone, true, true, null)]
    [InlineData(true, null, true, true, null)]
    [InlineData(true, "", true, true, null)]
    [InlineData(true, "   ", true, true, null)]
    [InlineData(true, "not a phone", true, true, null)]
    [InlineData(true, "+94771234567;ext=1", true, true, null)]
    [InlineData(true, WorkPhone, false, true, null)]
    [InlineData(true, WorkPhone, true, false, null)]
    public async Task OwningTenant_DisclosureUsesOnlyOptedInAssignedWorkPhone(
        bool enabled, string? phone, bool assigned, bool active, string? expected)
    {
        using var factory = new AuthApiFactory();
        var seeded = Seed(factory, enabled, phone, assigned, active);
        using var tenant = Client(factory, seeded.Tenant, UserRole.Tenant);

        using var response = await tenant.GetAsync($"/api/maintenance-requests/{seeded.Request}");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.True(response.Headers.CacheControl?.NoStore);
        var body = await response.Content.ReadFromJsonAsync<JsonElement>();
        Assert.Equal(expected, body.GetProperty("assignedTechnicianContactPhone").GetString());
        Assert.Equal(assigned ? "Mike Reyes" : null, body.GetProperty("assignedTechnicianName").GetString());
        Assert.DoesNotContain(PrivatePhone, body.GetRawText());
        Assert.DoesNotContain("private-tech@example.test", body.GetRawText());
        Assert.False(body.TryGetProperty("phoneNumber", out _));
        Assert.False(body.TryGetProperty("email", out _));
        Assert.False(body.TryGetProperty("maintenanceContactEnabled", out _));
        var summary = await tenant.GetFromJsonAsync<JsonElement>($"/api/maintenance-requests/tenant/{seeded.Tenant}");
        Assert.False(summary[0].TryGetProperty("assignedTechnicianContactPhone", out _));
        Assert.DoesNotContain(WorkPhone, summary.GetRawText());
    }

    [Fact]
    public async Task AnotherTenant_CannotRetrieveRequestOrContact()
    {
        using var factory = new AuthApiFactory();
        var seeded = Seed(factory, true, WorkPhone);
        using var tenant = Client(factory, Guid.NewGuid(), UserRole.Tenant);
        using var response = await tenant.GetAsync($"/api/maintenance-requests/{seeded.Request}");
        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
        Assert.DoesNotContain(WorkPhone, await response.Content.ReadAsStringAsync());
    }

    [Theory]
    [InlineData(UserRole.Landlord)]
    [InlineData(UserRole.Admin)]
    [InlineData(UserRole.MaintenanceTechnician)]
    public async Task OtherRequestReaders_DoNotReceiveTenantContactProjection(UserRole role)
    {
        using var factory = new AuthApiFactory();
        var seeded = Seed(factory, true, WorkPhone);
        var actor = role == UserRole.MaintenanceTechnician ? seeded.Technician : Guid.NewGuid();
        if (role == UserRole.Landlord)
        {
            using var scope = factory.Services.CreateScope();
            var db = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
            var request = db.MaintenanceRequests.Single(item => item.Id == seeded.Request);
            db.Properties.Add(new Property { Id = request.PropertyId, LandlordId = actor, Title = "Owned", Address = "Test", City = "Test" });
            db.SaveChanges();
        }
        using var client = Client(factory, actor, role);
        var detail = await client.GetFromJsonAsync<JsonElement>($"/api/maintenance-requests/{seeded.Request}");
        Assert.Equal(JsonValueKind.Null, detail.GetProperty("assignedTechnicianContactPhone").ValueKind);
    }

    [Fact]
    public async Task ExplicitSave_CopiesSnapshotAndLaterPrivateChangesPreserveIt()
    {
        using var factory = new AuthApiFactory();
        var seeded = Seed(factory, false, null);
        using var technician = Client(factory, seeded.Technician, UserRole.MaintenanceTechnician);
        using var tenant = Client(factory, seeded.Tenant, UserRole.Tenant);
        var initial = await technician.GetFromJsonAsync<JsonElement>("/api/auth/me");
        Assert.False(initial.GetProperty("maintenanceContactEnabled").GetBoolean());
        Assert.False(initial.TryGetProperty("maintenanceContactPhone", out _));

        // The editor explicitly submits the selected profile number on Save.
        using var saved = await Save(technician, PrivatePhone, true);
        Assert.Equal(HttpStatusCode.OK, saved.StatusCode);
        var profile = await saved.Content.ReadFromJsonAsync<JsonElement>();
        Assert.Equal(PrivatePhone, profile.GetProperty("maintenanceContactPhone").GetString());
        using var privateChange = await technician.PutAsJsonAsync("/api/auth/profile",
            new { fullName = "Mike Reyes", phoneNumber = "+94119998888" });
        privateChange.EnsureSuccessStatusCode();
        profile = await technician.GetFromJsonAsync<JsonElement>("/api/auth/me");
        Assert.Equal("+94119998888", profile.GetProperty("phoneNumber").GetString());
        Assert.Equal(PrivatePhone, profile.GetProperty("maintenanceContactPhone").GetString());
        var detail = await tenant.GetFromJsonAsync<JsonElement>($"/api/maintenance-requests/{seeded.Request}");
        Assert.Equal(PrivatePhone, detail.GetProperty("assignedTechnicianContactPhone").GetString());

        using var disabled = await technician.PutAsJsonAsync("/api/auth/profile",
            new { fullName = "Mike Reyes", phoneNumber = "+94119998888", maintenanceContactEnabled = false });
        disabled.EnsureSuccessStatusCode();
        profile = await technician.GetFromJsonAsync<JsonElement>("/api/auth/me");
        Assert.Equal(PrivatePhone, profile.GetProperty("maintenanceContactPhone").GetString());
        detail = await tenant.GetFromJsonAsync<JsonElement>($"/api/maintenance-requests/{seeded.Request}");
        Assert.Equal(JsonValueKind.Null, detail.GetProperty("assignedTechnicianContactPhone").ValueKind);

        using var custom = await Save(technician, "  " + WorkPhone + "  ", true);
        custom.EnsureSuccessStatusCode();
        detail = await tenant.GetFromJsonAsync<JsonElement>($"/api/maintenance-requests/{seeded.Request}");
        Assert.Equal(WorkPhone, detail.GetProperty("assignedTechnicianContactPhone").GetString());
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("  ")]
    [InlineData("12-----")]
    [InlineData("1234567890123456")]
    [InlineData("+94771234567?call=true")]
    [InlineData("+94---------------------------------771234567")]
    public async Task EnabledInvalidNumber_IsRejectedWithoutChangingProfile(string? phone)
    {
        using var factory = new AuthApiFactory();
        var seeded = Seed(factory, false, null);
        using var technician = Client(factory, seeded.Technician, UserRole.MaintenanceTechnician);
        using var response = await Save(technician, phone, true);
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        using var scope = factory.Services.CreateScope();
        var user = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>().Users.Single(u => u.Id == seeded.Technician);
        Assert.False(user.MaintenanceContactEnabled);
        Assert.Null(user.MaintenanceContactPhone);
        Assert.Equal(PrivatePhone, user.PhoneNumber);
        Assert.Equal("Mike Reyes", user.FullName);
    }

    [Theory]
    [InlineData(UserRole.Tenant)]
    [InlineData(UserRole.Landlord)]
    [InlineData(UserRole.Admin)]
    public async Task OtherProfiles_CannotConfigureOrReceiveWorkContact(UserRole role)
    {
        using var factory = new AuthApiFactory();
        using var client = Client(factory, Guid.NewGuid(), role);
        using var response = await Save(client, WorkPhone, true);
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        var profile = await client.GetFromJsonAsync<JsonElement>("/api/auth/me");
        Assert.False(profile.TryGetProperty("maintenanceContactPhone", out _));
        Assert.False(profile.TryGetProperty("maintenanceContactEnabled", out _));
    }

    [Fact]
    public async Task TenantHistory_RetainsEventsButRedactsStaffNotes()
    {
        using var factory = new AuthApiFactory();
        var seeded = Seed(factory, false, null);
        const string note = "Internal supplier and staff information.";
        using (var scope = factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
            db.MaintenanceStatusHistories.Add(new MaintenanceStatusHistory {
                MaintenanceRequestId = seeded.Request, FromStatus = MaintenanceRequestStatus.Triaged,
                ToStatus = MaintenanceRequestStatus.Assigned, Notes = note });
            db.SaveChanges();
        }
        using var tenant = Client(factory, seeded.Tenant, UserRole.Tenant);
        var history = await tenant.GetFromJsonAsync<JsonElement>($"/api/maintenance-requests/{seeded.Request}/history");
        Assert.Equal(1, history.GetArrayLength());
        Assert.Equal(2, history[0].GetProperty("toStatus").GetInt32());
        Assert.Equal(JsonValueKind.Null, history[0].GetProperty("notes").ValueKind);
        Assert.DoesNotContain(note, history.GetRawText());
        using var technician = Client(factory, seeded.Technician, UserRole.MaintenanceTechnician);
        var staffHistory = await technician.GetFromJsonAsync<JsonElement>($"/api/maintenance-requests/{seeded.Request}/history");
        Assert.Equal(note, staffHistory[0].GetProperty("notes").GetString());
    }

    private static Task<HttpResponseMessage> Save(HttpClient client, string? phone, bool enabled) =>
        client.PutAsJsonAsync("/api/auth/profile", new { fullName = "Saved Technician", phoneNumber = PrivatePhone,
            maintenanceContactPhone = phone, maintenanceContactEnabled = enabled });

    private static HttpClient Client(AuthApiFactory factory, Guid id, UserRole role)
    {
        factory.EnsureActiveUser(id, role);
        using var scope = factory.Services.CreateScope();
        var user = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>().Users.Single(u => u.Id == id);
        var token = scope.ServiceProvider.GetRequiredService<IJwtTokenService>().CreateToken(user);
        var client = factory.CreateHttpsClient();
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token.Value);
        return client;
    }

    private static (Guid Tenant, Guid Technician, Guid Request) Seed(AuthApiFactory factory,
        bool enabled, string? phone, bool assigned = true, bool active = true)
    {
        var tenant = Guid.NewGuid();
        var technician = Guid.NewGuid();
        factory.EnsureActiveUser(tenant, UserRole.Tenant);
        factory.EnsureActiveUser(technician, UserRole.MaintenanceTechnician);
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
        var user = db.Users.Single(u => u.Id == technician);
        user.FullName = "Mike Reyes";
        user.Email = "private-tech@example.test";
        user.PhoneNumber = PrivatePhone;
        user.MaintenanceContactEnabled = enabled;
        user.MaintenanceContactPhone = phone;
        user.IsActive = active;
        var request = new MaintenanceRequest { TenantId = tenant, PropertyId = Guid.NewGuid(),
            TechnicianId = assigned ? technician : null, Title = "Bedroom outlet", Description = "No power.",
            Status = assigned ? MaintenanceRequestStatus.Assigned : MaintenanceRequestStatus.Submitted };
        db.MaintenanceRequests.Add(request);
        db.SaveChanges();
        return (tenant, technician, request.Id);
    }
}
