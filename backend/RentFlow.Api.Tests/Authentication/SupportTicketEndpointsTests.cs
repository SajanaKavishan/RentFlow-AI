using System.IdentityModel.Tokens.Jwt;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Claims;
using System.Text;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.IdentityModel.Tokens;
using RentFlow.Api.Data;
using RentFlow.Api.DTOs.SupportTickets;
using RentFlow.Api.Models;
using Xunit;

namespace RentFlow.Api.Tests.Authentication;

public sealed class SupportTicketEndpointsTests
{
    private static readonly Guid UserA = Guid.Parse("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");
    private static readonly Guid UserB = Guid.Parse("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb");

    [Theory]
    [InlineData("POST", "/api/support-tickets")]
    [InlineData("GET", "/api/support-tickets/mine")]
    public async Task Endpoints_RequireAuthentication(string method, string path)
    {
        using var factory = new AuthApiFactory();
        using var client = factory.CreateHttpsClient();
        using var request = new HttpRequestMessage(new HttpMethod(method), path);
        if (method == "POST")
        {
            request.Content = JsonContent.Create(new
            {
                category = "TechnicalIssue",
                subject = "Cannot load profile",
                message = "The profile page does not finish loading."
            });
        }

        var response = await client.SendAsync(request);

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Theory]
    [InlineData(UserRole.Tenant)]
    [InlineData(UserRole.Landlord)]
    [InlineData(UserRole.MaintenanceTechnician)]
    [InlineData(UserRole.Admin)]
    public async Task Create_DerivesOwnerFromJwt_ForEveryAuthenticatedRole(UserRole role)
    {
        using var factory = new AuthApiFactory();
        using var client = AuthorizedClient(factory, UserA, role);

        var response = await client.PostAsJsonAsync("/api/support-tickets", new
        {
            category = "AccountLogin",
            subject = "  Login warning  ",
            message = "  I receive a warning after signing in.  ",
            userId = UserB,
            role = UserRole.Admin.ToString()
        });
        var ticket = await response.Content.ReadFromJsonAsync<SupportTicketResponseDto>();

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        Assert.Equal("/api/support-tickets/mine", response.Headers.Location?.OriginalString);
        Assert.NotNull(ticket);
        Assert.Equal("AccountLogin", ticket!.Category);
        Assert.Equal("Login warning", ticket.Subject);
        Assert.Equal("I receive a warning after signing in.", ticket.Message);
        Assert.Equal("Open", ticket.Status);
        Assert.Equal(ticket.CreatedAt, ticket.UpdatedAt);

        using var scope = factory.Services.CreateScope();
        var stored = Assert.Single(scope.ServiceProvider.GetRequiredService<ApplicationDbContext>().SupportTickets);
        Assert.Equal(UserA, stored.UserId);
        Assert.Equal(SupportTicketStatus.Open, stored.Status);
    }

    [Theory]
    [InlineData("", "Subject", "Message")]
    [InlineData("0", "Subject", "Message")]
    [InlineData("technicalissue", "Subject", "Message")]
    [InlineData("TechnicalIssue", "   ", "Message")]
    [InlineData("TechnicalIssue", "Subject", "   ")]
    public async Task Create_RejectsUnsupportedOrWhitespaceValues(
        string category,
        string subject,
        string message)
    {
        using var factory = new AuthApiFactory();
        using var client = AuthorizedClient(factory, UserA);

        var response = await client.PostAsJsonAsync("/api/support-tickets", new
        {
            category,
            subject,
            message
        });

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        using var scope = factory.Services.CreateScope();
        Assert.Empty(scope.ServiceProvider.GetRequiredService<ApplicationDbContext>().SupportTickets);
    }

    [Fact]
    public async Task Create_RejectsSubjectAndMessageAbovePersistedLimits()
    {
        using var factory = new AuthApiFactory();
        using var client = AuthorizedClient(factory, UserA);

        var longSubject = await client.PostAsJsonAsync("/api/support-tickets", new
        {
            category = "Other",
            subject = new string('s', 201),
            message = "Valid message"
        });
        var longMessage = await client.PostAsJsonAsync("/api/support-tickets", new
        {
            category = "Other",
            subject = "Valid subject",
            message = new string('m', 4001)
        });

        Assert.Equal(HttpStatusCode.BadRequest, longSubject.StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, longMessage.StatusCode);
    }

    [Fact]
    public async Task Mine_ReturnsOnlyJwtOwnersTickets_NewestFirst()
    {
        using var factory = new AuthApiFactory();
        factory.EnsureActiveUser(UserA, UserRole.Tenant);
        factory.EnsureActiveUser(UserB, UserRole.Landlord);
        var older = SeedTicket(factory, UserA, "Older", DateTimeOffset.UtcNow.AddMinutes(-2));
        var newer = SeedTicket(factory, UserA, "Newer", DateTimeOffset.UtcNow);
        SeedTicket(factory, UserB, "Foreign", DateTimeOffset.UtcNow.AddMinutes(1));
        using var client = AuthorizedClient(factory, UserA);

        var tickets = await client.GetFromJsonAsync<List<SupportTicketResponseDto>>(
            "/api/support-tickets/mine");

        Assert.NotNull(tickets);
        Assert.Equal([newer.Id, older.Id], tickets!.Select(ticket => ticket.Id));
        Assert.DoesNotContain(tickets, ticket => ticket.Subject == "Foreign");
    }

    private static SupportTicket SeedTicket(
        AuthApiFactory factory,
        Guid userId,
        string subject,
        DateTimeOffset createdAt)
    {
        var ticket = new SupportTicket
        {
            UserId = userId,
            Category = SupportTicketCategory.Other,
            Subject = subject,
            Message = $"{subject} message",
            Status = SupportTicketStatus.Open,
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
        UserRole role = UserRole.Tenant)
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
