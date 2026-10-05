using System.Net;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using RentFlow.Api.Data;
using RentFlow.Api.Models;
using Xunit;

namespace RentFlow.Api.Tests.Authentication;

public sealed class PublicLandlordSummaryEndpointsTests
{
    [Fact]
    public async Task ProfileWithImage_ExposesAvailabilityWithoutStorageOrContactFields()
    {
        await using var factory = new AuthApiFactory();
        var propertyId = await SeedPropertyAsync(factory, withImage: true);
        using var client = factory.CreateHttpsClient();
        using var response = await client.GetAsync($"/api/properties/{propertyId}/landlord-summary");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        Assert.True(json.RootElement.GetProperty("hasProfileImage").GetBoolean());
        Assert.Equal(new[] { "displayName", "hasProfileImage", "memberSinceYear" },
            json.RootElement.EnumerateObject().Select(p => p.Name).Order().ToArray());
        Assert.DoesNotContain("profiles/", json.RootElement.GetRawText());
        // Image metadata can exist while the image itself is unavailable.
        using var missing = await client.GetAsync($"/api/properties/{propertyId}/landlord-summary/image");
        Assert.Equal(HttpStatusCode.NotFound, missing.StatusCode);
    }

    [Fact]
    public async Task Listings_IncludeOnlyThisLandlordsAvailableTenantBrowseProperties()
    {
        await using var factory = new AuthApiFactory();
        var propertyId = await SeedPropertyAsync(factory);
        var otherPropertyId = await SeedPropertyAsync(factory);
        Guid upcomingId;
        Guid unavailableId;
        using (var scope = factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
            var anchor = await db.Properties.SingleAsync(p => p.Id == propertyId);
            var upcoming = new Property { Id = Guid.NewGuid(), LandlordId = anchor.LandlordId,
                Title = "Upcoming home", Description = "Available soon", Address = "2 Lake Road", City = "Colombo",
                IsAvailable = true, AvailableFrom = DateOnly.FromDateTime(DateTime.UtcNow.AddMonths(1)) };
            var unavailable = new Property { Id = Guid.NewGuid(), LandlordId = anchor.LandlordId,
                Title = "Unavailable home", Description = "Not currently offered", Address = "3 Lake Road", City = "Colombo",
                IsAvailable = false };
            db.Properties.AddRange(upcoming, unavailable);
            await db.SaveChangesAsync();
            upcomingId = upcoming.Id;
            unavailableId = unavailable.Id;
        }
        using var client = factory.CreateHttpsClient();
        using var response = await client.GetAsync($"/api/properties/{propertyId}/landlord-summary/properties");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        var items = json.RootElement.EnumerateArray().ToArray();
        var ids = items.Select(item => item.GetProperty("id").GetGuid()).ToArray();
        Assert.Equal(2, ids.Length);
        Assert.Contains(propertyId, ids);
        Assert.Contains(upcomingId, ids);
        Assert.DoesNotContain(otherPropertyId, ids);
        Assert.DoesNotContain(unavailableId, ids);
        Assert.All(items, item => Assert.True(item.GetProperty("isAvailable").GetBoolean()));
        using var browse = await client.GetAsync("/api/properties?isAvailable=true");
        browse.EnsureSuccessStatusCode();
        using var browseJson = JsonDocument.Parse(await browse.Content.ReadAsStringAsync());
        var browseIds = browseJson.RootElement.EnumerateArray().Select(p => p.GetProperty("id").GetGuid()).ToArray();
        Assert.All(ids, id => Assert.Contains(id, browseIds));
        Assert.Equal(browseJson.RootElement[0].EnumerateObject().Select(p => p.Name).Order(),
            items[0].EnumerateObject().Select(p => p.Name).Order());
        foreach (var field in new[] { "phoneNumber", "email", "passwordHash", "tokenVersion", "storageKey", "notificationPreferences" })
            Assert.DoesNotContain($"\"{field}\"", json.RootElement.GetRawText());
        Assert.DoesNotContain("landlord@example.test", json.RootElement.GetRawText());
        Assert.DoesNotContain("+94112223344", json.RootElement.GetRawText());
    }

    [Theory]
    [InlineData(false, UserRole.Landlord)]
    [InlineData(true, UserRole.Tenant)]
    [InlineData(true, UserRole.Admin)]
    public async Task InvalidLandlord_ReturnsNotFoundForEveryPublicProfileResource(bool active, UserRole role)
    {
        await using var factory = new AuthApiFactory();
        var propertyId = await SeedPropertyAsync(factory, landlordActive: active, role: role, withImage: true);
        using var client = factory.CreateHttpsClient();
        foreach (var suffix in new[] { "", "/image", "/properties" })
        {
            using var response = await client.GetAsync($"/api/properties/{propertyId}/landlord-summary{suffix}");
            Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
            Assert.DoesNotContain("landlord@example.test", await response.Content.ReadAsStringAsync());
        }
    }

    [Fact]
    public async Task UnknownProperty_DoesNotExposeAUserLookup()
    {
        await using var factory = new AuthApiFactory();
        using var client = factory.CreateHttpsClient();
        foreach (var suffix in new[] { "", "/image", "/properties" })
        {
            using var response = await client.GetAsync($"/api/properties/{Guid.NewGuid()}/landlord-summary{suffix}");
            Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
        }
    }

    [Fact]
    public async Task ProfileWithNoAvailableListings_ReturnsAnEmptyList()
    {
        await using var factory = new AuthApiFactory();
        var propertyId = await SeedPropertyAsync(factory);
        using (var scope = factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
            (await db.Properties.SingleAsync(p => p.Id == propertyId)).IsAvailable = false;
            await db.SaveChangesAsync();
        }
        using var client = factory.CreateHttpsClient();
        using var response = await client.GetAsync($"/api/properties/{propertyId}/landlord-summary/properties");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        Assert.Empty(json.RootElement.EnumerateArray());
    }

    [Fact]
    public async Task Summary_ReturnsOnlyApprovedFieldsForPropertyLandlord()
    {
        await using var factory = new AuthApiFactory();
        var propertyId = await SeedPropertyAsync(factory);
        using var client = factory.CreateHttpsClient();

        using var response = await client.GetAsync(
            $"/api/properties/{propertyId}/landlord-summary");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        using var document = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        var root = document.RootElement;
        Assert.Equal(
            new[] { "displayName", "hasProfileImage", "memberSinceYear" },
            root.EnumerateObject().Select(item => item.Name).Order().ToArray());
        Assert.Equal("Lena Landlord", root.GetProperty("displayName").GetString());
        Assert.Equal(2022, root.GetProperty("memberSinceYear").GetInt32());
        Assert.False(root.GetProperty("hasProfileImage").GetBoolean());
        Assert.DoesNotContain("landlord@example.test", root.GetRawText());
        Assert.DoesNotContain("+94112223344", root.GetRawText());
    }

    [Fact]
    public async Task Image_IsServedOnlyThroughTheAssociatedProperty()
    {
        await using var factory = new AuthApiFactory();
        var bytes = new byte[] { 0xFF, 0xD8, 0xFF, 0xD9 };
        var propertyId = await SeedPropertyAsync(factory, withImage: true);
        await factory.FileStorage.UploadAsync(
            new MemoryStream(bytes),
            "profiles/landlord.jpg",
            "image/jpeg");
        using var client = factory.CreateHttpsClient();

        using var response = await client.GetAsync(
            $"/api/properties/{propertyId}/landlord-summary/image");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal("image/jpeg", response.Content.Headers.ContentType?.MediaType);
        Assert.Equal(bytes, await response.Content.ReadAsByteArrayAsync());

        using var unrelated = await client.GetAsync(
            $"/api/properties/{Guid.NewGuid()}/landlord-summary/image");
        Assert.Equal(HttpStatusCode.NotFound, unrelated.StatusCode);
    }

    [Fact]
    public async Task Summary_ReturnsNotFoundForUnknownPropertyOrInactiveLandlord()
    {
        await using var factory = new AuthApiFactory();
        var propertyId = await SeedPropertyAsync(factory, landlordActive: false);
        using var client = factory.CreateHttpsClient();

        using var inactive = await client.GetAsync(
            $"/api/properties/{propertyId}/landlord-summary");
        using var unknown = await client.GetAsync(
            $"/api/properties/{Guid.NewGuid()}/landlord-summary");

        Assert.Equal(HttpStatusCode.NotFound, inactive.StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, unknown.StatusCode);
    }

    [Fact]
    public async Task Summary_RejectsPropertyOwnerWithNonLandlordRole()
    {
        await using var factory = new AuthApiFactory();
        var propertyId = await SeedPropertyAsync(factory, role: UserRole.Tenant);
        using var client = factory.CreateHttpsClient();

        using var response = await client.GetAsync(
            $"/api/properties/{propertyId}/landlord-summary");

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    private static async Task<Guid> SeedPropertyAsync(
        AuthApiFactory factory,
        bool landlordActive = true,
        UserRole role = UserRole.Landlord,
        bool withImage = false)
    {
        using var scope = factory.Services.CreateScope();
        var context = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
        var landlord = new ApplicationUser
        {
            Id = Guid.NewGuid(),
            FullName = "Lena Landlord",
            Email = "landlord@example.test",
            NormalizedEmail = "LANDLORD@EXAMPLE.TEST",
            PhoneNumber = "+94112223344",
            PasswordHash = "private-password-hash",
            Role = role,
            IsActive = landlordActive,
            CreatedAt = new DateTimeOffset(2022, 6, 15, 0, 0, 0, TimeSpan.Zero),
            UpdatedAt = DateTimeOffset.UtcNow
        };
        var property = new Property
        {
            Id = Guid.NewGuid(),
            LandlordId = landlord.Id,
            Landlord = landlord,
            Title = "Lake View Apartment",
            Description = "Test listing",
            Address = "18 Lake Road",
            City = "Colombo",
            MonthlyRent = 120000,
            Bedrooms = 2,
            Bathrooms = 2,
            IsAvailable = true
        };
        context.Users.Add(landlord);
        context.Properties.Add(property);

        if (withImage)
        {
            context.UserProfileImages.Add(new UserProfileImage
            {
                UserId = landlord.Id,
                User = landlord,
                StorageKey = "profiles/landlord.jpg",
                ContentType = "image/jpeg",
                FileSizeBytes = 4,
                UpdatedAt = DateTimeOffset.UtcNow
            });
        }

        await context.SaveChangesAsync();
        return property.Id;
    }
}
