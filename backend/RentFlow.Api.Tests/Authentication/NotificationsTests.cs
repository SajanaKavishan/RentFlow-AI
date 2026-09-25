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
using RentFlow.Api.DTOs.Notifications;
using RentFlow.Api.Models;
using Xunit;

namespace RentFlow.Api.Tests.Authentication;

public sealed class NotificationsTests
{
    private static readonly Guid UserA = Guid.Parse("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");
    private static readonly Guid UserB = Guid.Parse("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb");

    [Fact]
    public async Task Notifications_RequireAuthentication()
    {
        using var factory = new AuthApiFactory();
        using var client = factory.CreateHttpsClient();

        var response = await client.GetAsync("/api/notifications");

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task Notifications_AreIsolatedByJwtRecipient()
    {
        using var factory = new AuthApiFactory();
        var owned = await SeedNotificationAsync(factory, UserA, "Owned");
        var foreign = await SeedNotificationAsync(factory, UserB, "Foreign");
        using var client = AuthorizedClient(factory, UserA);

        var page = await client.GetFromJsonAsync<NotificationPageResponseDto>("/api/notifications");
        var foreignRead = await client.PatchAsync($"/api/notifications/{foreign.Id}/read", null);

        Assert.NotNull(page);
        Assert.Single(page!.Items);
        Assert.Equal(owned.Id, page.Items[0].Id);
        Assert.Equal(HttpStatusCode.NotFound, foreignRead.StatusCode);
    }

    [Theory]
    [InlineData(UserRole.Tenant)]
    [InlineData(UserRole.Landlord)]
    [InlineData(UserRole.MaintenanceTechnician)]
    [InlineData(UserRole.Admin)]
    public async Task RecipientScope_IsEnforcedForEveryAuthenticatedRole(UserRole role)
    {
        using var factory = new AuthApiFactory();
        var owned = await SeedNotificationAsync(factory, UserA, $"{role} owned");
        var foreign = await SeedNotificationAsync(factory, UserB, $"{role} foreign");
        using var client = AuthorizedClient(factory, UserA, role);

        var page = await client.GetFromJsonAsync<NotificationPageResponseDto>(
            "/api/notifications?pageSize=100");
        var count = await client.GetFromJsonAsync<UnreadNotificationCountResponseDto>(
            "/api/notifications/unread-count");
        var ownedRead = await client.PatchAsync($"/api/notifications/{owned.Id}/read", null);
        var foreignRead = await client.PatchAsync($"/api/notifications/{foreign.Id}/read", null);

        Assert.NotNull(page);
        Assert.Single(page!.Items);
        Assert.Equal(owned.Id, page.Items[0].Id);
        Assert.NotNull(count);
        Assert.Equal(1, count!.UnreadCount);
        Assert.Equal(HttpStatusCode.OK, ownedRead.StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, foreignRead.StatusCode);
    }

    [Fact]
    public async Task Notifications_AreNewestFirstAndPaginated()
    {
        using var factory = new AuthApiFactory();
        var oldest = await SeedNotificationAsync(factory, UserA, "Oldest", DateTimeOffset.UtcNow.AddMinutes(-3));
        var newest = await SeedNotificationAsync(factory, UserA, "Newest", DateTimeOffset.UtcNow);
        using var client = AuthorizedClient(factory, UserA);

        var page = await client.GetFromJsonAsync<NotificationPageResponseDto>(
            "/api/notifications?page=1&pageSize=1");

        Assert.NotNull(page);
        Assert.Single(page!.Items);
        Assert.Equal(newest.Id, page.Items[0].Id);
        Assert.Equal(2, page.Pagination.TotalCount);
        Assert.Equal(2, page.Pagination.TotalPages);
        Assert.True(page.Pagination.HasNextPage);

        var secondPage = await client.GetFromJsonAsync<NotificationPageResponseDto>(
            "/api/notifications?page=2&pageSize=1");

        Assert.NotNull(secondPage);
        Assert.Equal(oldest.Id, secondPage!.Items[0].Id);
        Assert.True(secondPage.Pagination.HasPreviousPage);
    }

    [Fact]
    public async Task UnreadCount_IsLimitedToCurrentUser()
    {
        using var factory = new AuthApiFactory();
        await SeedNotificationAsync(factory, UserA, "Unread A");
        await SeedNotificationAsync(factory, UserA, "Read A", readAt: DateTimeOffset.UtcNow);
        await SeedNotificationAsync(factory, UserB, "Unread B");
        using var client = AuthorizedClient(factory, UserA);

        var response = await client.GetFromJsonAsync<UnreadNotificationCountResponseDto>(
            "/api/notifications/unread-count");

        Assert.NotNull(response);
        Assert.Equal(1, response!.UnreadCount);
    }

    [Fact]
    public async Task MarkAsRead_ReturnsExplicitReadState_AndIsIdempotent()
    {
        using var factory = new AuthApiFactory();
        var notification = await SeedNotificationAsync(factory, UserA, "Unread");
        using var client = AuthorizedClient(factory, UserA);

        var first = await client.PatchAsJsonAsync(
            $"/api/notifications/{notification.Id}/read", new { });
        var firstBody = await first.Content.ReadFromJsonAsync<NotificationResponseDto>();
        var second = await client.PatchAsJsonAsync(
            $"/api/notifications/{notification.Id}/read", new { });
        var secondBody = await second.Content.ReadFromJsonAsync<NotificationResponseDto>();

        Assert.Equal(HttpStatusCode.OK, first.StatusCode);
        Assert.Equal(HttpStatusCode.OK, second.StatusCode);
        Assert.NotNull(firstBody);
        Assert.NotNull(secondBody);
        Assert.True(firstBody!.IsRead);
        Assert.NotNull(firstBody.ReadAt);
        Assert.Equal(firstBody.ReadAt, secondBody!.ReadAt);
    }

    [Fact]
    public async Task ForeignNotificationId_ReturnsNotFoundWhenMarkedAsRead()
    {
        using var factory = new AuthApiFactory();
        var foreign = await SeedNotificationAsync(factory, UserB, "Foreign");
        using var client = AuthorizedClient(factory, UserA);

        var response = await client.PatchAsync(
            $"/api/notifications/{foreign.Id}/read", null);

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    private static HttpClient AuthorizedClient(
        AuthApiFactory factory,
        Guid userId,
        UserRole role = UserRole.Tenant)
    {
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
            new Claim("role", role.ToString())
        };
        var token = new JwtSecurityToken(
            issuer: "RentFlow.Api.Tests",
            audience: "RentFlow.TestClients",
            claims: claims,
            expires: DateTime.UtcNow.AddMinutes(10),
            signingCredentials: credentials);
        return new JwtSecurityTokenHandler().WriteToken(token);
    }

    private static async Task<Notification> SeedNotificationAsync(
        AuthApiFactory factory,
        Guid recipientId,
        string title,
        DateTimeOffset? createdAt = null,
        DateTimeOffset? readAt = null)
    {
        var notification = new Notification
        {
            Id = Guid.NewGuid(),
            RecipientId = recipientId,
            EventType = "test.event",
            RelatedResourceType = "TestResource",
            RelatedResourceId = Guid.NewGuid(),
            Title = title,
            Message = $"{title} message",
            CreatedAt = createdAt ?? DateTimeOffset.UtcNow,
            ReadAt = readAt
        };

        using var scope = factory.Services.CreateScope();
        var context = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
        context.Notifications.Add(notification);
        await context.SaveChangesAsync();
        return notification;
    }
}
