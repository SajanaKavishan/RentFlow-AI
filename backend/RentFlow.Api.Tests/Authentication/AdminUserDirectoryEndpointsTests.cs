using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using RentFlow.Api.Data;
using RentFlow.Api.DTOs.Auth;
using RentFlow.Api.Models;
using RentFlow.Api.Services;
using Xunit;

namespace RentFlow.Api.Tests.Authentication;

public sealed class AdminUserDirectoryEndpointsTests
{
    private const string Password = "Admin1!Password";

    [Fact]
    public async Task GetPage_RequiresAuthentication()
    {
        using var factory = new AuthApiFactory();
        using var client = factory.CreateHttpsClient();

        using var response = await client.GetAsync("/api/admin/users");

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Theory]
    [InlineData(UserRole.Tenant)]
    [InlineData(UserRole.Landlord)]
    [InlineData(UserRole.MaintenanceTechnician)]
    public async Task GetPage_RejectsNonAdminUsers(UserRole role)
    {
        using var factory = new AuthApiFactory();
        var user = await SeedUserAndLoginAsync(
            factory,
            $"{role.ToString().ToLowerInvariant()}@example.com",
            role);
        using var client = AuthorizedClient(factory, user.Token);

        using var response = await client.GetAsync("/api/admin/users");

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Theory]
    [InlineData(false, UserRole.Admin)]
    [InlineData(true, UserRole.Landlord)]
    public async Task GetPage_RejectsStaleAdminJwtAfterDatabaseChange(
        bool isActive,
        UserRole databaseRole)
    {
        using var factory = new AuthApiFactory();
        var admin = await SeedUserAndLoginAsync(
            factory,
            "admin@example.com",
            UserRole.Admin);
        await UpdateUserAsync(factory, admin.UserId, isActive, databaseRole);
        using var client = AuthorizedClient(factory, admin.Token);

        using var response = await client.GetAsync("/api/admin/users");

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task GetPage_ReturnsRealUsersInDeterministicPages()
    {
        using var factory = new AuthApiFactory();
        var admin = await SeedUserAndLoginAsync(
            factory,
            "admin@example.com",
            UserRole.Admin,
            new DateTimeOffset(2026, 1, 1, 0, 0, 0, TimeSpan.Zero));
        var tenantId = await SeedUserAsync(
            factory,
            "tenant@example.com",
            UserRole.Tenant,
            true,
            new DateTimeOffset(2026, 1, 2, 0, 0, 0, TimeSpan.Zero),
            "Taylor Tenant");
        var landlordId = await SeedUserAsync(
            factory,
            "landlord@example.com",
            UserRole.Landlord,
            true,
            new DateTimeOffset(2026, 1, 3, 0, 0, 0, TimeSpan.Zero),
            "Lee Landlord");
        var technicianId = await SeedUserAsync(
            factory,
            "technician@example.com",
            UserRole.MaintenanceTechnician,
            false,
            new DateTimeOffset(2026, 1, 4, 0, 0, 0, TimeSpan.Zero),
            "Morgan Technician");
        using var client = AuthorizedClient(factory, admin.Token);

        var first = await client.GetFromJsonAsync<AdminUserDirectoryPageDto>(
            "/api/admin/users?page=1&pageSize=2");
        var second = await client.GetFromJsonAsync<AdminUserDirectoryPageDto>(
            "/api/admin/users?page=2&pageSize=2");

        Assert.NotNull(first);
        Assert.Equal([technicianId, landlordId], first!.Items.Select(user => user.Id));
        Assert.Equal(1, first.Pagination.Page);
        Assert.Equal(2, first.Pagination.PageSize);
        Assert.Equal(4, first.Pagination.TotalCount);
        Assert.Equal(2, first.Pagination.TotalPages);
        Assert.True(first.Pagination.HasNextPage);
        Assert.False(first.Pagination.HasPreviousPage);

        Assert.NotNull(second);
        Assert.Equal([tenantId, admin.UserId], second!.Items.Select(user => user.Id));
        Assert.False(second.Pagination.HasNextPage);
        Assert.True(second.Pagination.HasPreviousPage);
    }

    [Fact]
    public async Task GetPage_AppliesSearchRoleAndActiveFiltersToItemsAndTotal()
    {
        using var factory = new AuthApiFactory();
        var admin = await SeedUserAndLoginAsync(
            factory,
            "admin@example.com",
            UserRole.Admin);
        var expectedId = await SeedUserAsync(
            factory,
            "pending.technician@example.com",
            UserRole.MaintenanceTechnician,
            false,
            DateTimeOffset.UtcNow.AddMinutes(1),
            "Casey Chen");
        await SeedUserAsync(
            factory,
            "active.chen@example.com",
            UserRole.MaintenanceTechnician,
            true,
            DateTimeOffset.UtcNow.AddMinutes(2),
            "Active Technician");
        await SeedUserAsync(
            factory,
            "tenant.chen@example.com",
            UserRole.Tenant,
            false,
            DateTimeOffset.UtcNow.AddMinutes(3),
            "Chen Tenant");
        using var client = AuthorizedClient(factory, admin.Token);

        var page = await client.GetFromJsonAsync<AdminUserDirectoryPageDto>(
            "/api/admin/users?search=CHEN&role=MaintenanceTechnician&isActive=false");

        Assert.NotNull(page);
        var item = Assert.Single(page!.Items);
        Assert.Equal(expectedId, item.Id);
        Assert.Equal("Casey Chen", item.FullName);
        Assert.Equal("pending.technician@example.com", item.Email);
        Assert.Equal(UserRole.MaintenanceTechnician, item.Role);
        Assert.False(item.IsActive);
        Assert.Equal(1, page.Pagination.TotalCount);
        Assert.Equal(1, page.Pagination.TotalPages);
    }

    [Fact]
    public async Task GetPage_ReturnsSafeExplicitResponseFieldsOnly()
    {
        using var factory = new AuthApiFactory();
        var admin = await SeedUserAndLoginAsync(
            factory,
            "admin@example.com",
            UserRole.Admin);
        using var client = AuthorizedClient(factory, admin.Token);

        using var response = await client.GetAsync("/api/admin/users");
        var responseText = await response.Content.ReadAsStringAsync();
        using var body = JsonDocument.Parse(responseText);
        var item = body.RootElement.GetProperty("items")[0];
        var propertyNames = item.EnumerateObject()
            .Select(property => property.Name)
            .OrderBy(name => name, StringComparer.Ordinal)
            .ToArray();

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal(
            ["createdAt", "email", "fullName", "id", "isActive", "role"],
            propertyNames);
        Assert.DoesNotContain("password", responseText, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("token", responseText, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("digest", responseText, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("jwt", responseText, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task GetPage_ReturnsEmptyPageWithoutFabricatedTotals()
    {
        using var factory = new AuthApiFactory();
        var admin = await SeedUserAndLoginAsync(
            factory,
            "admin@example.com",
            UserRole.Admin);
        using var client = AuthorizedClient(factory, admin.Token);

        var page = await client.GetFromJsonAsync<AdminUserDirectoryPageDto>(
            "/api/admin/users?search=no-matching-user");

        Assert.NotNull(page);
        Assert.Empty(page!.Items);
        Assert.Equal(0, page.Pagination.TotalCount);
        Assert.Equal(0, page.Pagination.TotalPages);
        Assert.False(page.Pagination.HasNextPage);
        Assert.False(page.Pagination.HasPreviousPage);
    }

    [Theory]
    [InlineData("?page=0")]
    [InlineData("?pageSize=0")]
    [InlineData("?pageSize=101")]
    [InlineData("?role=admin")]
    [InlineData("?role=Owner")]
    [InlineData("?isActive=maybe")]
    public async Task GetPage_RejectsInvalidQueryParameters(string query)
    {
        using var factory = new AuthApiFactory();
        var admin = await SeedUserAndLoginAsync(
            factory,
            "admin@example.com",
            UserRole.Admin);
        using var client = AuthorizedClient(factory, admin.Token);

        using var response = await client.GetAsync($"/api/admin/users{query}");

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task GetPage_RejectsOverlongSearch()
    {
        using var factory = new AuthApiFactory();
        var admin = await SeedUserAndLoginAsync(
            factory,
            "admin@example.com",
            UserRole.Admin);
        using var client = AuthorizedClient(factory, admin.Token);

        using var response = await client.GetAsync(
            $"/api/admin/users?search={new string('a', 321)}");

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    private static HttpClient AuthorizedClient(AuthApiFactory factory, string token)
    {
        var client = factory.CreateHttpsClient();
        client.DefaultRequestHeaders.Authorization =
            new AuthenticationHeaderValue("Bearer", token);
        return client;
    }

    private static async Task<(Guid UserId, string Token)> SeedUserAndLoginAsync(
        AuthApiFactory factory,
        string email,
        UserRole role,
        DateTimeOffset? createdAt = null)
    {
        var userId = await SeedUserAsync(
            factory,
            email,
            role,
            true,
            createdAt ?? DateTimeOffset.UtcNow,
            $"Test {role}");
        using var client = factory.CreateHttpsClient();
        using var response = await client.PostAsJsonAsync(
            "/api/auth/login",
            new { email, password = Password });
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        return (userId, body.RootElement.GetProperty("accessToken").GetString()!);
    }

    private static async Task<Guid> SeedUserAsync(
        AuthApiFactory factory,
        string email,
        UserRole role,
        bool isActive,
        DateTimeOffset createdAt,
        string fullName)
    {
        using var scope = factory.Services.CreateScope();
        var services = scope.ServiceProvider;
        var context = services.GetRequiredService<ApplicationDbContext>();
        var user = new ApplicationUser
        {
            Id = Guid.NewGuid(),
            FullName = fullName,
            Email = email,
            NormalizedEmail = AuthService.NormalizeEmail(email),
            PhoneNumber = "+94770000000",
            Role = role,
            IsActive = isActive,
            CreatedAt = createdAt,
            UpdatedAt = createdAt
        };
        var hasher = services.GetRequiredService<IPasswordHasher<ApplicationUser>>();
        user.PasswordHash = hasher.HashPassword(user, Password);
        context.Users.Add(user);
        await context.SaveChangesAsync();
        return user.Id;
    }

    private static async Task UpdateUserAsync(
        AuthApiFactory factory,
        Guid userId,
        bool isActive,
        UserRole role)
    {
        using var scope = factory.Services.CreateScope();
        var context = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
        var user = await context.Users.SingleAsync(candidate => candidate.Id == userId);
        user.IsActive = isActive;
        user.Role = role;
        await context.SaveChangesAsync();
    }
}
