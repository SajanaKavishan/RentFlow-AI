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

public sealed class NotificationEventsTests
{
    private static readonly Guid TenantA = Guid.Parse("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");
    private static readonly Guid TenantB = Guid.Parse("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb");
    private static readonly Guid LandlordA = Guid.Parse("11111111-1111-1111-1111-111111111111");
    private static readonly Guid LandlordB = Guid.Parse("22222222-2222-2222-2222-222222222222");

    [Fact]
    public async Task SuccessfulViewingAndApplicationDecisions_CreateTenantNotifications()
    {
        using var factory = new AuthApiFactory();
        var property = await SeedPropertyAsync(factory, LandlordA);
        var approvedViewing = await SeedViewingAsync(factory, TenantA, property.Id);
        var rejectedViewing = await SeedViewingAsync(factory, TenantA, property.Id);
        var approvedApplication = await SeedApplicationAsync(
            factory, TenantA, property.Id, RentalApplicationStatus.UnderReview);
        var rejectedApplication = await SeedApplicationAsync(
            factory, TenantA, property.Id, RentalApplicationStatus.UnderReview);
        var changesApplication = await SeedApplicationAsync(
            factory, TenantA, property.Id, RentalApplicationStatus.UnderReview);
        using var landlord = AuthorizedClient(factory, LandlordA, UserRole.Landlord);

        Assert.Equal(HttpStatusCode.OK, (await landlord.PatchAsJsonAsync(
            $"/api/viewings/{approvedViewing.Id}/approve", new { landlordResponse = "Confirmed." })).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await landlord.PatchAsJsonAsync(
            $"/api/viewings/{rejectedViewing.Id}/reject", new { landlordResponse = "Unavailable." })).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await landlord.PatchAsJsonAsync(
            $"/api/rental-applications/{approvedApplication.Id}/approve", new { landlordResponse = "Approved." })).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await landlord.PatchAsJsonAsync(
            $"/api/rental-applications/{rejectedApplication.Id}/reject", new { landlordResponse = "Not eligible." })).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await landlord.PatchAsJsonAsync(
            $"/api/rental-applications/{changesApplication.Id}/request-changes", new { landlordResponse = "Please revise." })).StatusCode);

        using var tenant = AuthorizedClient(factory, TenantA, UserRole.Tenant);
        var page = await tenant.GetFromJsonAsync<NotificationPageResponseDto>(
            "/api/notifications?pageSize=100");

        Assert.NotNull(page);
        Assert.Equal(5, page!.Items.Count);
        Assert.Equal(
            [
                "rental_application.changes_requested",
                "rental_application.rejected",
                "rental_application.approved",
                "viewing.rejected",
                "viewing.approved"
            ],
            page.Items.Select(item => item.EventType).ToArray());
        Assert.All(page.Items, item => Assert.False(item.IsRead));
        Assert.Contains(page.Items, item => item.RelatedResourceType == "ViewingRequest"
            && item.RelatedResourceId == approvedViewing.Id);
        Assert.Contains(page.Items, item => item.RelatedResourceType == "RentalApplication"
            && item.RelatedResourceId == changesApplication.Id);

        using var otherTenant = AuthorizedClient(factory, TenantB, UserRole.Tenant);
        var otherPage = await otherTenant.GetFromJsonAsync<NotificationPageResponseDto>(
            "/api/notifications");
        Assert.NotNull(otherPage);
        Assert.Empty(otherPage!.Items);
    }

    [Fact]
    public async Task InvalidDeniedAndRepeatedDecisions_DoNotCreateExtraNotifications()
    {
        using var factory = new AuthApiFactory();
        var property = await SeedPropertyAsync(factory, LandlordA);
        var viewing = await SeedViewingAsync(factory, TenantA, property.Id);
        var application = await SeedApplicationAsync(
            factory, TenantA, property.Id, RentalApplicationStatus.UnderReview);
        using var landlord = AuthorizedClient(factory, LandlordA, UserRole.Landlord);
        using var otherLandlord = AuthorizedClient(factory, LandlordB, UserRole.Landlord);

        Assert.Equal(HttpStatusCode.BadRequest, (await landlord.PatchAsJsonAsync(
            $"/api/viewings/{viewing.Id}/reject", new { landlordResponse = " " })).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await otherLandlord.PatchAsJsonAsync(
            $"/api/viewings/{viewing.Id}/approve", new { landlordResponse = "Denied." })).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await landlord.PatchAsJsonAsync(
            $"/api/viewings/{viewing.Id}/approve", new { landlordResponse = "Approved." })).StatusCode);
        Assert.Equal(HttpStatusCode.Conflict, (await landlord.PatchAsJsonAsync(
            $"/api/viewings/{viewing.Id}/approve", new { landlordResponse = "Again." })).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await landlord.PatchAsJsonAsync(
            $"/api/rental-applications/{application.Id}/reject", new { landlordResponse = " " })).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await otherLandlord.PatchAsJsonAsync(
            $"/api/rental-applications/{application.Id}/approve", new { landlordResponse = "Denied." })).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await landlord.PatchAsJsonAsync(
            $"/api/rental-applications/{application.Id}/approve", new { landlordResponse = "Approved." })).StatusCode);
        Assert.Equal(HttpStatusCode.Conflict, (await landlord.PatchAsJsonAsync(
            $"/api/rental-applications/{application.Id}/approve", new { landlordResponse = "Again." })).StatusCode);

        using var tenant = AuthorizedClient(factory, TenantA, UserRole.Tenant);
        var page = await tenant.GetFromJsonAsync<NotificationPageResponseDto>(
            "/api/notifications");
        Assert.NotNull(page);
        Assert.Equal(2, page!.Items.Count);
        Assert.Contains(page.Items, item => item.EventType == "viewing.approved");
        Assert.Contains(page.Items, item => item.EventType == "rental_application.approved");
    }

    [Fact]
    public async Task ViewingCreationAndApplicationSubmissions_NotifyThePersistedPropertyLandlords()
    {
        using var factory = new AuthApiFactory();
        var propertyA = await SeedPropertyAsync(factory, LandlordA);
        var propertyB = await SeedPropertyAsync(factory, LandlordB);
        using var tenant = AuthorizedClient(factory, TenantA, UserRole.Tenant);

        var viewingResponse = await tenant.PostAsJsonAsync(
            "/api/viewings",
            new
            {
                propertyId = propertyA.Id,
                requestedDateTime = DateTimeOffset.UtcNow.AddDays(3),
                tenantMessage = "I would like to view the property."
            });
        var applicationResponse = await tenant.PostAsJsonAsync(
            "/api/rental-applications",
            new
            {
                propertyId = propertyB.Id,
                moveInDate = DateOnly.FromDateTime(DateTime.UtcNow.AddDays(30)),
                monthlyIncome = 250000m,
                occupation = "Engineer",
                numberOfOccupants = 1,
                tenantNote = "Application note."
            });

        Assert.Equal(HttpStatusCode.Created, viewingResponse.StatusCode);
        Assert.Equal(HttpStatusCode.Created, applicationResponse.StatusCode);
        var application = await applicationResponse.Content
            .ReadFromJsonAsync<RentalApplicationResponseForTest>();
        Assert.NotNull(application);

        Assert.Equal(HttpStatusCode.OK, (await tenant.PatchAsync(
            $"/api/rental-applications/{application!.Id}/submit", null)).StatusCode);
        using var landlordB = AuthorizedClient(factory, LandlordB, UserRole.Landlord);
        Assert.Equal(HttpStatusCode.OK, (await landlordB.PatchAsync(
            $"/api/rental-applications/{application.Id}/review", null)).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await landlordB.PatchAsJsonAsync(
            $"/api/rental-applications/{application.Id}/request-changes",
            new { landlordResponse = "Please update the application." })).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await tenant.PatchAsync(
            $"/api/rental-applications/{application.Id}/submit", null)).StatusCode);

        using var landlordA = AuthorizedClient(factory, LandlordA, UserRole.Landlord);
        var landlordANotifications = await landlordA.GetFromJsonAsync<NotificationPageResponseDto>(
            "/api/notifications?pageSize=100");
        var landlordBNotifications = await landlordB.GetFromJsonAsync<NotificationPageResponseDto>(
            "/api/notifications?pageSize=100");

        Assert.NotNull(landlordANotifications);
        Assert.NotNull(landlordBNotifications);
        Assert.Single(landlordANotifications!.Items);
        Assert.Equal("viewing.created", landlordANotifications.Items[0].EventType);
        Assert.Equal("ViewingRequest", landlordANotifications.Items[0].RelatedResourceType);
        Assert.Equal(2, landlordBNotifications!.Items.Count);
        Assert.Equal(
            ["rental_application.resubmitted", "rental_application.submitted"],
            landlordBNotifications.Items.Select(item => item.EventType).ToArray());

        using var unrelatedTenant = AuthorizedClient(factory, TenantB, UserRole.Tenant);
        var unrelatedTenantNotifications = await unrelatedTenant.GetFromJsonAsync<NotificationPageResponseDto>(
            "/api/notifications");
        Assert.NotNull(unrelatedTenantNotifications);
        Assert.Empty(unrelatedTenantNotifications!.Items);
    }

    [Fact]
    public async Task DisabledViewingUpdates_SuppressFutureEventsButKeepStoredNotifications()
    {
        using var factory = new AuthApiFactory();
        var property = await SeedPropertyAsync(factory, LandlordA);
        var viewing = await SeedViewingAsync(factory, TenantA, property.Id);
        var existing = new Notification
        {
            Id = Guid.NewGuid(),
            RecipientId = TenantA,
            EventType = "viewing.created",
            RelatedResourceType = "ViewingRequest",
            RelatedResourceId = Guid.NewGuid(),
            Title = "Existing viewing update",
            Message = "This notification existed before the preference changed.",
            CreatedAt = DateTimeOffset.UtcNow.AddMinutes(-5)
        };
        await SeedAsync(factory, context =>
        {
            context.Notifications.Add(existing);
            context.NotificationPreferences.Add(new NotificationPreference
            {
                UserId = TenantA,
                ViewingUpdatesEnabled = false,
                RentalApplicationUpdatesEnabled = true
            });
        });
        using var landlord = AuthorizedClient(factory, LandlordA, UserRole.Landlord);

        Assert.Equal(HttpStatusCode.OK, (await landlord.PatchAsJsonAsync(
            $"/api/viewings/{viewing.Id}/approve",
            new { landlordResponse = "Approved." })).StatusCode);

        using var tenant = AuthorizedClient(factory, TenantA, UserRole.Tenant);
        var page = await tenant.GetFromJsonAsync<NotificationPageResponseDto>(
            "/api/notifications?pageSize=100");
        Assert.NotNull(page);
        var delivered = Assert.Single(page!.Items);
        Assert.Equal(existing.Id, delivered.Id);
    }

    [Fact]
    public async Task DisabledRentalApplicationUpdates_SuppressFutureDecisionEvents()
    {
        using var factory = new AuthApiFactory();
        var property = await SeedPropertyAsync(factory, LandlordA);
        var application = await SeedApplicationAsync(
            factory,
            TenantA,
            property.Id,
            RentalApplicationStatus.UnderReview);
        await SeedAsync(factory, context => context.NotificationPreferences.Add(
            new NotificationPreference
            {
                UserId = TenantA,
                ViewingUpdatesEnabled = true,
                RentalApplicationUpdatesEnabled = false
            }));
        using var landlord = AuthorizedClient(factory, LandlordA, UserRole.Landlord);

        Assert.Equal(HttpStatusCode.OK, (await landlord.PatchAsJsonAsync(
            $"/api/rental-applications/{application.Id}/approve",
            new { landlordResponse = "Approved." })).StatusCode);

        using var tenant = AuthorizedClient(factory, TenantA, UserRole.Tenant);
        var page = await tenant.GetFromJsonAsync<NotificationPageResponseDto>(
            "/api/notifications");
        Assert.NotNull(page);
        Assert.Empty(page!.Items);
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

    private static async Task<Property> SeedPropertyAsync(
        AuthApiFactory factory,
        Guid landlordId)
    {
        var property = new Property
        {
            Id = Guid.NewGuid(),
            LandlordId = landlordId,
            Title = "Notification test property",
            Description = "Property used for notification events.",
            Address = "1 Notification Street",
            City = "Colombo",
            MonthlyRent = 100000m,
            Bedrooms = 2,
            Bathrooms = 1,
            IsAvailable = true,
            CreatedAt = DateTimeOffset.UtcNow
        };
        await SeedAsync(factory, context => context.Properties.Add(property));
        return property;
    }

    private static async Task<ViewingRequest> SeedViewingAsync(
        AuthApiFactory factory,
        Guid tenantId,
        Guid propertyId)
    {
        var viewing = new ViewingRequest
        {
            Id = Guid.NewGuid(),
            TenantId = tenantId,
            PropertyId = propertyId,
            RequestedDateTime = DateTimeOffset.UtcNow.AddDays(5),
            Status = ViewingStatus.Pending,
            CreatedAt = DateTimeOffset.UtcNow
        };
        await SeedAsync(factory, context => context.ViewingRequests.Add(viewing));
        return viewing;
    }

    private static async Task<RentalApplication> SeedApplicationAsync(
        AuthApiFactory factory,
        Guid tenantId,
        Guid propertyId,
        RentalApplicationStatus status)
    {
        var application = new RentalApplication
        {
            Id = Guid.NewGuid(),
            TenantId = tenantId,
            PropertyId = propertyId,
            MoveInDate = DateOnly.FromDateTime(DateTime.UtcNow.AddDays(30)),
            MonthlyIncome = 250000m,
            Occupation = "Engineer",
            NumberOfOccupants = 1,
            Status = status,
            CreatedAt = DateTimeOffset.UtcNow
        };
        await SeedAsync(factory, context => context.RentalApplications.Add(application));
        return application;
    }

    private sealed class RentalApplicationResponseForTest
    {
        public Guid Id { get; init; }
    }

    private static async Task SeedAsync(
        AuthApiFactory factory,
        Action<ApplicationDbContext> seed)
    {
        using var scope = factory.Services.CreateScope();
        var context = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
        seed(context);
        await context.SaveChangesAsync();
    }
}
