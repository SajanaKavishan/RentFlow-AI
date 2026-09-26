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
using RentFlow.Api.DTOs.SupportTickets;
using RentFlow.Api.Models;
using Xunit;

namespace RentFlow.Api.Tests.Authentication;

public sealed class AdminSupportTicketEndpointsTests
{
    private static readonly Guid AdminId = Guid.Parse("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");
    private static readonly Guid RequesterA = Guid.Parse("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb");
    private static readonly Guid RequesterB = Guid.Parse("cccccccc-cccc-cccc-cccc-cccccccccccc");

    [Theory]
    [InlineData("GET", "/api/admin/support-tickets")]
    [InlineData("GET", "/api/admin/support-tickets/11111111-1111-1111-1111-111111111111")]
    [InlineData("PATCH", "/api/admin/support-tickets/11111111-1111-1111-1111-111111111111/status")]
    public async Task Endpoints_RequireAuthentication(string method, string path)
    {
        using var factory = new AuthApiFactory();
        using var client = factory.CreateHttpsClient();
        using var request = new HttpRequestMessage(new HttpMethod(method), path);
        if (method == "PATCH") request.Content = JsonContent.Create(new { status = "Resolved" });

        using var response = await client.SendAsync(request);

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Theory]
    [InlineData(UserRole.Tenant)]
    [InlineData(UserRole.Landlord)]
    [InlineData(UserRole.MaintenanceTechnician)]
    public async Task List_RejectsEveryNonAdminRole(UserRole role)
    {
        using var factory = new AuthApiFactory();
        using var client = AuthorizedClient(factory, Guid.NewGuid(), role);

        using var response = await client.GetAsync("/api/admin/support-tickets");

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Fact]
    public async Task DetailAndStatus_RejectNonAdminUsers()
    {
        using var factory = new AuthApiFactory();
        using var client = AuthorizedClient(factory, RequesterA, UserRole.Tenant);
        var id = Guid.NewGuid();

        using var detail = await client.GetAsync($"/api/admin/support-tickets/{id}");
        using var update = await client.PatchAsJsonAsync(
            $"/api/admin/support-tickets/{id}/status", new { status = "Resolved" });

        Assert.Equal(HttpStatusCode.Forbidden, detail.StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, update.StatusCode);
    }

    [Fact]
    public async Task ActiveAdminPolicy_RejectsAdminDeactivatedAfterTokenIssue()
    {
        using var factory = new AuthApiFactory();
        using var client = AuthorizedClient(factory, AdminId, UserRole.Admin);
        using (var scope = factory.Services.CreateScope())
        {
            var context = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
            var admin = await context.Users.SingleAsync(user => user.Id == AdminId);
            admin.IsActive = false;
            await context.SaveChangesAsync();
        }

        using var response = await client.GetAsync("/api/admin/support-tickets");

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task List_AppliesPaginationStatusCategoryAndSafeRequesterSearch()
    {
        using var factory = new AuthApiFactory();
        SeedRequester(factory, RequesterA, "Lee Requester", "lee@example.test");
        SeedRequester(factory, RequesterB, "Morgan Other", "morgan@example.test");
        var expected = SeedTicket(factory, RequesterA, SupportTicketCategory.Payment,
            SupportTicketStatus.Open, "Missing receipt", DateTimeOffset.UtcNow);
        SeedTicket(factory, RequesterA, SupportTicketCategory.TechnicalIssue,
            SupportTicketStatus.Open, "Page problem", DateTimeOffset.UtcNow.AddMinutes(1));
        SeedTicket(factory, RequesterB, SupportTicketCategory.Payment,
            SupportTicketStatus.Resolved, "Old payment", DateTimeOffset.UtcNow.AddMinutes(2));
        using var client = AuthorizedClient(factory, AdminId, UserRole.Admin);

        var page = await client.GetFromJsonAsync<AdminSupportTicketPageDto>(
            "/api/admin/support-tickets?page=1&pageSize=1&status=Open&category=Payment&search=LEE");

        Assert.NotNull(page);
        var item = Assert.Single(page!.Items);
        Assert.Equal(expected.Id, item.Id);
        Assert.Equal("Payment", item.Category);
        Assert.Equal("Open", item.Status);
        Assert.Equal("Lee Requester", item.RequesterFullName);
        Assert.Equal("lee@example.test", item.RequesterEmail);
        Assert.Equal(1, page.Pagination.Page);
        Assert.Equal(1, page.Pagination.PageSize);
        Assert.Equal(1, page.Pagination.TotalCount);
        Assert.Equal(1, page.Pagination.TotalPages);
        Assert.False(page.Pagination.HasNextPage);
        Assert.False(page.Pagination.HasPreviousPage);
    }

    [Fact]
    public async Task List_SearchesSubjectAndReturnsNewestFirst()
    {
        using var factory = new AuthApiFactory();
        SeedRequester(factory, RequesterA, "Requester", "requester@example.test");
        var older = SeedTicket(factory, RequesterA, SupportTicketCategory.Other,
            SupportTicketStatus.Open, "Account assistance", DateTimeOffset.UtcNow.AddMinutes(-2));
        var newer = SeedTicket(factory, RequesterA, SupportTicketCategory.Other,
            SupportTicketStatus.InProgress, "Account follow-up", DateTimeOffset.UtcNow);
        using var client = AuthorizedClient(factory, AdminId, UserRole.Admin);

        var page = await client.GetFromJsonAsync<AdminSupportTicketPageDto>(
            "/api/admin/support-tickets?search=account");

        Assert.NotNull(page);
        Assert.Equal([newer.Id, older.Id], page!.Items.Select(ticket => ticket.Id));
    }

    [Fact]
    public async Task ListAndDetail_ReturnOnlyExplicitAdminUiFields()
    {
        using var factory = new AuthApiFactory();
        SeedRequester(factory, RequesterA, "Safe Requester", "safe@example.test");
        var ticket = SeedTicket(factory, RequesterA, SupportTicketCategory.AccountLogin,
            SupportTicketStatus.Open, "Cannot log in", DateTimeOffset.UtcNow, "Detailed problem description");
        using var client = AuthorizedClient(factory, AdminId, UserRole.Admin);

        using var listResponse = await client.GetAsync("/api/admin/support-tickets");
        using var detailResponse = await client.GetAsync($"/api/admin/support-tickets/{ticket.Id}");
        using var listJson = JsonDocument.Parse(await listResponse.Content.ReadAsStringAsync());
        using var detailJson = JsonDocument.Parse(await detailResponse.Content.ReadAsStringAsync());
        var listFields = listJson.RootElement.GetProperty("items")[0].EnumerateObject()
            .Select(property => property.Name).OrderBy(name => name, StringComparer.Ordinal).ToArray();
        var detailFields = detailJson.RootElement.EnumerateObject()
            .Select(property => property.Name).OrderBy(name => name, StringComparer.Ordinal).ToArray();

        Assert.Equal(HttpStatusCode.OK, listResponse.StatusCode);
        Assert.Equal(HttpStatusCode.OK, detailResponse.StatusCode);
        Assert.Equal(
            ["category", "createdAt", "id", "requesterEmail", "requesterFullName", "status", "subject"],
            listFields);
        Assert.Equal(
            ["category", "createdAt", "id", "message", "requesterEmail", "requesterFullName", "status", "subject", "updatedAt"],
            detailFields);
        var combined = await listResponse.Content.ReadAsStringAsync()
            + await detailResponse.Content.ReadAsStringAsync();
        Assert.DoesNotContain("password", combined, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("token", combined, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("phone", combined, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("role", combined, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("userId", combined, StringComparison.OrdinalIgnoreCase);
    }

    [Theory]
    [InlineData(SupportTicketStatus.Open, "InProgress")]
    [InlineData(SupportTicketStatus.Open, "Resolved")]
    [InlineData(SupportTicketStatus.InProgress, "Resolved")]
    public async Task Status_AllowsOnlyForwardProductTransitions(
        SupportTicketStatus initial,
        string requested)
    {
        using var factory = new AuthApiFactory();
        SeedRequester(factory, RequesterA, "Requester", "requester@example.test");
        var ticket = SeedTicket(factory, RequesterA, SupportTicketCategory.Other,
            initial, "Transition ticket", DateTimeOffset.UtcNow.AddHours(-1));
        using var client = AuthorizedClient(factory, AdminId, UserRole.Admin);

        using var response = await client.PatchAsJsonAsync(
            $"/api/admin/support-tickets/{ticket.Id}/status", new { status = requested });
        var result = await response.Content.ReadFromJsonAsync<AdminSupportTicketStatusResponseDto>();

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.NotNull(result);
        Assert.Equal(ticket.Id, result!.Id);
        Assert.Equal(requested, result.Status);
        Assert.True(result.UpdatedAt > ticket.CreatedAt);
        using var scope = factory.Services.CreateScope();
        var stored = await scope.ServiceProvider.GetRequiredService<ApplicationDbContext>()
            .SupportTickets.SingleAsync(item => item.Id == ticket.Id);
        Assert.Equal(Enum.Parse<SupportTicketStatus>(requested), stored.Status);
    }

    [Theory]
    [InlineData(SupportTicketStatus.Open, "Open")]
    [InlineData(SupportTicketStatus.InProgress, "Open")]
    [InlineData(SupportTicketStatus.Resolved, "InProgress")]
    [InlineData(SupportTicketStatus.Resolved, "Open")]
    public async Task Status_RejectsSameOrBackwardTransitions(
        SupportTicketStatus initial,
        string requested)
    {
        using var factory = new AuthApiFactory();
        SeedRequester(factory, RequesterA, "Requester", "requester@example.test");
        var ticket = SeedTicket(factory, RequesterA, SupportTicketCategory.Other,
            initial, "Transition ticket", DateTimeOffset.UtcNow.AddHours(-1));
        using var client = AuthorizedClient(factory, AdminId, UserRole.Admin);

        using var response = await client.PatchAsJsonAsync(
            $"/api/admin/support-tickets/{ticket.Id}/status", new { status = requested });

        Assert.Equal(HttpStatusCode.Conflict, response.StatusCode);
        using var scope = factory.Services.CreateScope();
        var stored = await scope.ServiceProvider.GetRequiredService<ApplicationDbContext>()
            .SupportTickets.AsNoTracking().SingleAsync(item => item.Id == ticket.Id);
        Assert.Equal(initial, stored.Status);
    }

    [Theory]
    [InlineData("?page=0")]
    [InlineData("?pageSize=0")]
    [InlineData("?pageSize=101")]
    [InlineData("?status=1")]
    [InlineData("?status=open")]
    [InlineData("?category=Unknown")]
    public async Task List_RejectsInvalidQueries(string query)
    {
        using var factory = new AuthApiFactory();
        using var client = AuthorizedClient(factory, AdminId, UserRole.Admin);

        using var response = await client.GetAsync($"/api/admin/support-tickets{query}");

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task Status_RejectsUnknownStatusAndMissingTicket()
    {
        using var factory = new AuthApiFactory();
        using var client = AuthorizedClient(factory, AdminId, UserRole.Admin);

        using var invalid = await client.PatchAsJsonAsync(
            $"/api/admin/support-tickets/{Guid.NewGuid()}/status", new { status = "Closed" });
        using var missing = await client.PatchAsJsonAsync(
            $"/api/admin/support-tickets/{Guid.NewGuid()}/status", new { status = "Resolved" });
        using var missingDetail = await client.GetAsync(
            $"/api/admin/support-tickets/{Guid.NewGuid()}");

        Assert.Equal(HttpStatusCode.BadRequest, invalid.StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, missing.StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, missingDetail.StatusCode);
    }

    private static void SeedRequester(
        AuthApiFactory factory,
        Guid id,
        string fullName,
        string email)
    {
        factory.EnsureActiveUser(id, UserRole.Tenant);
        using var scope = factory.Services.CreateScope();
        var context = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
        var user = context.Users.Single(item => item.Id == id);
        user.FullName = fullName;
        user.Email = email;
        user.NormalizedEmail = email.ToUpperInvariant();
        context.SaveChanges();
    }

    private static SupportTicket SeedTicket(
        AuthApiFactory factory,
        Guid userId,
        SupportTicketCategory category,
        SupportTicketStatus status,
        string subject,
        DateTimeOffset createdAt,
        string message = "Support ticket message")
    {
        var ticket = new SupportTicket
        {
            UserId = userId,
            Category = category,
            Subject = subject,
            Message = message,
            Status = status,
            CreatedAt = createdAt,
            UpdatedAt = createdAt
        };
        using var scope = factory.Services.CreateScope();
        var context = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
        context.SupportTickets.Add(ticket);
        context.SaveChanges();
        return ticket;
    }

    private static HttpClient AuthorizedClient(
        AuthApiFactory factory,
        Guid userId,
        UserRole role)
    {
        factory.EnsureActiveUser(userId, role);
        var client = factory.CreateHttpsClient();
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue(
            "Bearer", CreateToken(userId, role));
        return client;
    }

    private static string CreateToken(Guid userId, UserRole role)
    {
        var credentials = new SigningCredentials(
            new SymmetricSecurityKey(Encoding.UTF8.GetBytes(
                "test-only-signing-key-that-is-at-least-32-bytes-long")),
            SecurityAlgorithms.HmacSha256);
        var claims = new[]
        {
            new Claim(JwtRegisteredClaimNames.Sub, userId.ToString()),
            new Claim("role", role.ToString()),
            new Claim("token_version", "0")
        };
        var token = new JwtSecurityToken(
            issuer: "RentFlow.Api.Tests",
            audience: "RentFlow.TestClients",
            claims: claims,
            expires: DateTime.UtcNow.AddMinutes(10),
            signingCredentials: credentials);
        return new JwtSecurityTokenHandler().WriteToken(token);
    }
}
