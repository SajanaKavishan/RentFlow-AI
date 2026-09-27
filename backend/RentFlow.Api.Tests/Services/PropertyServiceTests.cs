using System.ComponentModel.DataAnnotations;
using Microsoft.EntityFrameworkCore;
using RentFlow.Api.Data;
using RentFlow.Api.DTOs;
using RentFlow.Api.Models;
using RentFlow.Api.Services;
using RentFlow.Api.Services.Interfaces;
using Xunit;

namespace RentFlow.Api.Tests.Services;

public class PropertyServiceTests
{
    [Fact]
    public async Task CreateAsync_CreatesPropertyWithAmenities()
    {
        await using var context = CreateContext();
        var imageService = new FakePropertyImageService();
        var service = new PropertyService(context, imageService);

        var landlordId = Guid.NewGuid();

        var dto = new CreatePropertyDto
        {
            Title = "Colombo Apartment",
            Description = "Modern apartment",
            Address = "Galle Road",
            City = "Colombo",
            Latitude = 6.927079,
            Longitude = 79.861244,
            GooglePlaceId = "  ChIJ-colombo-property  ",
            MonthlyRent = 85000m,
            Bedrooms = 2,
            Bathrooms = 1,
            Area = 1250m,
            AreaUnit = "sqft",
            Amenities = new List<string>
            {
                "Parking",
                "WiFi"
            }
        };

        var result = await service.CreateAsync(
            landlordId,
            dto);

        Assert.NotEqual(Guid.Empty, result.Id);
        Assert.Equal(landlordId, result.LandlordId);
        Assert.Equal("Colombo Apartment", result.Title);
        Assert.Equal("Colombo", result.City);
        Assert.Equal(6.927079, result.Latitude);
        Assert.Equal(79.861244, result.Longitude);
        Assert.Equal("ChIJ-colombo-property", result.GooglePlaceId);
        Assert.Equal(85000m, result.MonthlyRent);
        Assert.Equal(1250m, result.Area);
        Assert.Equal("sqft", result.AreaUnit);
        Assert.True(result.IsAvailable);
        Assert.Equal(2, result.Amenities.Count);

        var storedProperty = await context.Properties
            .Include(property => property.Amenities)
            .SingleAsync();

        Assert.Equal(result.Id, storedProperty.Id);
        Assert.Equal(result.Latitude, storedProperty.Latitude);
        Assert.Equal(result.Longitude, storedProperty.Longitude);
        Assert.Equal(result.GooglePlaceId, storedProperty.GooglePlaceId);
        Assert.Equal(2, storedProperty.Amenities.Count);
    }

    [Fact]
    public async Task GetByIdAsync_ReturnsExistingProperty()
    {
        await using var context = CreateContext();
        var imageService = new FakePropertyImageService();

        var property = AddProperty(context);

        await context.SaveChangesAsync();

        var service = new PropertyService(
            context,
            imageService);

        var result = await service.GetByIdAsync(property.Id);

        Assert.NotNull(result);
        Assert.Equal(property.Id, result.Id);
        Assert.Equal(property.Title, result.Title);
        Assert.Equal(property.City, result.City);
        Assert.Null(result.Latitude);
        Assert.Null(result.Longitude);
        Assert.Null(result.GooglePlaceId);
    }

    [Fact]
    public async Task GetByIdAsync_ReturnsNull_WhenPropertyDoesNotExist()
    {
        await using var context = CreateContext();
        var imageService = new FakePropertyImageService();

        var service = new PropertyService(
            context,
            imageService);

        var result = await service.GetByIdAsync(
            Guid.NewGuid());

        Assert.Null(result);
    }

    [Fact]
    public async Task UpdateAsync_UpdatesProperty_WhenLandlordOwnsProperty()
    {
        await using var context = CreateContext();
        var imageService = new FakePropertyImageService();

        var landlordId = Guid.NewGuid();

        var property = AddProperty(
            context,
            landlordId);

        await context.SaveChangesAsync();

        var service = new PropertyService(
            context,
            imageService);

        var dto = new UpdatePropertyDto
        {
            Title = "Updated Apartment",
            Description = "Updated description",
            Address = "Updated Address",
            City = "Kandy",
            Latitude = 7.290572,
            Longitude = 80.633728,
            GooglePlaceId = "ChIJ-kandy-property",
            MonthlyRent = 95000m,
            Bedrooms = 3,
            Bathrooms = 2,
            Area = 14.5m,
            AreaUnit = "perch",
            IsAvailable = false,
            Amenities = new List<string>
            {
                "Pool",
                "Security"
            }
        };

        var result = await service.UpdateAsync(
            property.Id,
            landlordId,
            dto);

        Assert.NotNull(result);
        Assert.Equal("Updated Apartment", result.Title);
        Assert.Equal("Kandy", result.City);
        Assert.Equal(7.290572, result.Latitude);
        Assert.Equal(80.633728, result.Longitude);
        Assert.Equal("ChIJ-kandy-property", result.GooglePlaceId);
        Assert.Equal(95000m, result.MonthlyRent);
        Assert.Equal(3, result.Bedrooms);
        Assert.Equal(2, result.Bathrooms);
        Assert.Equal(14.5m, result.Area);
        Assert.Equal("perch", result.AreaUnit);
        Assert.False(result.IsAvailable);
        Assert.Equal(2, result.Amenities.Count);
    }

    [Theory]
    [InlineData(-90.01, 79.0)]
    [InlineData(90.01, 79.0)]
    [InlineData(7.0, -180.01)]
    [InlineData(7.0, 180.01)]
    public void CreateDto_RejectsCoordinatesOutsideSupportedRanges(
        double latitude,
        double longitude)
    {
        var dto = ValidCreateDto();
        dto.Latitude = latitude;
        dto.Longitude = longitude;

        Assert.False(Validate(dto).IsValid);
    }

    [Fact]
    public void UpdateDto_RejectsIncompleteCoordinatePair()
    {
        var dto = new UpdatePropertyDto
        {
            Title = "Updated Apartment",
            Description = "Updated description",
            Address = "Updated Address",
            City = "Kandy",
            Latitude = 7.290572,
            Longitude = null,
            MonthlyRent = 95000m,
            Bedrooms = 3,
            Bathrooms = 2,
            IsAvailable = true
        };

        var validation = Validate(dto);

        Assert.False(validation.IsValid);
        Assert.Contains(validation.Results, result =>
            result.ErrorMessage == "Latitude and longitude must be provided together.");
    }

    [Fact]
    public void CreateDto_AcceptsLegacyAddressWithoutLocationMetadata()
    {
        var dto = ValidCreateDto();

        var validation = Validate(dto);

        Assert.True(validation.IsValid);
        Assert.Null(dto.Latitude);
        Assert.Null(dto.Longitude);
        Assert.Null(dto.GooglePlaceId);
    }

    [Fact]
    public async Task UpdateAsync_ReturnsNull_WhenLandlordDoesNotOwnProperty()
    {
        await using var context = CreateContext();
        var imageService = new FakePropertyImageService();

        var property = AddProperty(
            context,
            Guid.NewGuid());

        await context.SaveChangesAsync();

        var service = new PropertyService(
            context,
            imageService);

        var dto = new UpdatePropertyDto
        {
            Title = "Attempted Update",
            Description = "Should not work",
            Address = "Address",
            City = "Colombo",
            MonthlyRent = 50000m,
            Bedrooms = 1,
            Bathrooms = 1,
            IsAvailable = true,
            Amenities = new List<string>()
        };

        var result = await service.UpdateAsync(
            property.Id,
            Guid.NewGuid(),
            dto);

        Assert.Null(result);
    }

    [Fact]
    public async Task DeleteAsync_DeletesPropertyAndRequestsImageCleanup()
    {
        await using var context = CreateContext();
        var imageService = new FakePropertyImageService();

        var landlordId = Guid.NewGuid();

        var property = AddProperty(
            context,
            landlordId);

        await context.SaveChangesAsync();

        var service = new PropertyService(
            context,
            imageService);

        var result = await service.DeleteAsync(
            property.Id,
            landlordId);

        Assert.True(result);

        Assert.False(
            await context.Properties.AnyAsync(
                item => item.Id == property.Id));

        Assert.Equal(
            property.Id,
            imageService.DeletedPropertyId);

        Assert.Equal(
            landlordId,
            imageService.DeletedLandlordId);
    }

    [Fact]
    public async Task DeleteAsync_ReturnsFalseAndSkipsImageCleanup_WhenReferencedByRentalOffer()
    {
        await using var context = CreateContext();
        var imageService = new FakePropertyImageService();
        var property = AddProperty(context);
        context.RentalOffers.Add(new RentalOffer
        {
            RentalApplicationId = Guid.NewGuid(),
            TenantId = Guid.NewGuid(),
            PropertyId = property.Id,
            MonthlyRent = 85000m,
            SecurityDeposit = 170000m,
            ProposedStartDate = DateOnly.FromDateTime(DateTime.UtcNow.AddDays(30)),
            ProposedEndDate = DateOnly.FromDateTime(DateTime.UtcNow.AddMonths(12)),
            ExpiresAt = DateTimeOffset.UtcNow.AddDays(7)
        });
        await context.SaveChangesAsync();

        var service = new PropertyService(context, imageService);
        var result = await service.DeleteAsync(property.Id, property.LandlordId);

        Assert.False(result);
        Assert.True(await context.Properties.AnyAsync(item => item.Id == property.Id));
        Assert.Null(imageService.DeletedPropertyId);
    }

    [Fact]
    public async Task DeleteAsync_ReturnsFalseAndSkipsImageCleanup_WhenReferencedByLeaseAgreement()
    {
        await using var context = CreateContext();
        var imageService = new FakePropertyImageService();
        var property = AddProperty(context);
        context.LeaseAgreements.Add(new LeaseAgreement
        {
            RentalOfferId = Guid.NewGuid(),
            TenantId = Guid.NewGuid(),
            PropertyId = property.Id,
            MonthlyRent = 85000m,
            SecurityDeposit = 170000m,
            StartDate = DateOnly.FromDateTime(DateTime.UtcNow.AddDays(30)),
            EndDate = DateOnly.FromDateTime(DateTime.UtcNow.AddMonths(12))
        });
        await context.SaveChangesAsync();

        var service = new PropertyService(context, imageService);
        var result = await service.DeleteAsync(property.Id, property.LandlordId);

        Assert.False(result);
        Assert.True(await context.Properties.AnyAsync(item => item.Id == property.Id));
        Assert.Null(imageService.DeletedPropertyId);
    }

    [Fact]
    public async Task DeleteAsync_ReturnsFalse_WhenLandlordDoesNotOwnProperty()
    {
        await using var context = CreateContext();
        var imageService = new FakePropertyImageService();

        var property = AddProperty(
            context,
            Guid.NewGuid());

        await context.SaveChangesAsync();

        var service = new PropertyService(
            context,
            imageService);

        var result = await service.DeleteAsync(
            property.Id,
            Guid.NewGuid());

        Assert.False(result);

        Assert.True(
            await context.Properties.AnyAsync(
                item => item.Id == property.Id));

        Assert.Null(imageService.DeletedPropertyId);
    }

    private static ApplicationDbContext CreateContext()
    {
        var options =
            new DbContextOptionsBuilder<ApplicationDbContext>()
                .UseInMemoryDatabase(
                    $"PropertyServiceTests-{Guid.NewGuid()}")
                .Options;

        return new ApplicationDbContext(options);
    }

    private static CreatePropertyDto ValidCreateDto()
    {
        return new CreatePropertyDto
        {
            Title = "Legacy Property",
            Description = "A property with a textual location.",
            Address = "12 Lake Road",
            City = "Colombo",
            MonthlyRent = 75000m,
            Bedrooms = 2,
            Bathrooms = 1,
            Area = 900m,
            AreaUnit = "sqft"
        };
    }

    private static (bool IsValid, List<ValidationResult> Results) Validate(object instance)
    {
        var results = new List<ValidationResult>();
        var isValid = Validator.TryValidateObject(
            instance,
            new ValidationContext(instance),
            results,
            validateAllProperties: true);

        return (isValid, results);
    }

    private static Property AddProperty(
        ApplicationDbContext context,
        Guid? landlordId = null)
    {
        var property = new Property
        {
            Id = Guid.NewGuid(),
            LandlordId = landlordId ?? Guid.NewGuid(),
            Title = "Test Property",
            Description = "Test description",
            Address = "123 Test Street",
            City = "Colombo",
            MonthlyRent = 75000m,
            Bedrooms = 2,
            Bathrooms = 1,
            IsAvailable = true,
            CreatedAt = DateTimeOffset.UtcNow
        };

        property.Amenities.Add(
            new PropertyAmenity
            {
                Id = Guid.NewGuid(),
                PropertyId = property.Id,
                Name = "Parking"
            });

        context.Properties.Add(property);

        return property;
    }

    private sealed class FakePropertyImageService
        : IPropertyImageService
    {
        public Guid? DeletedPropertyId { get; private set; }
        public Guid? DeletedLandlordId { get; private set; }

        public Task<PropertyImageResponseDto> UploadAsync(
            Guid propertyId,
            Guid landlordId,
            Stream content,
            string originalFileName,
            string contentType,
            long fileSizeBytes,
            CancellationToken cancellationToken = default)
        {
            throw new NotImplementedException();
        }

        public Task<IReadOnlyList<PropertyImageResponseDto>>
            GetByPropertyAsync(
                Guid propertyId,
                CancellationToken cancellationToken = default)
        {
            throw new NotImplementedException();
        }

        public Task<string?> GenerateImageUrlAsync(
            Guid imageId,
            CancellationToken cancellationToken = default)
        {
            throw new NotImplementedException();
        }

        public Task<bool> DeleteAsync(
            Guid imageId,
            Guid landlordId,
            CancellationToken cancellationToken = default)
        {
            throw new NotImplementedException();
        }

        public Task DeleteAllForPropertyAsync(
            Guid propertyId,
            Guid landlordId,
            CancellationToken cancellationToken = default)
        {
            DeletedPropertyId = propertyId;
            DeletedLandlordId = landlordId;

            return Task.CompletedTask;
        }
    }
}
