using Microsoft.EntityFrameworkCore;
using RentFlow.Api.Data;
using RentFlow.Api.DTOs;
using RentFlow.Api.Models;
using RentFlow.Api.Services.Interfaces;

namespace RentFlow.Api.Services;

public class PropertyService : IPropertyService
{
    private readonly ApplicationDbContext _dbContext;
    private readonly IPropertyImageService _propertyImageService;

    public PropertyService(
        ApplicationDbContext dbContext,
        IPropertyImageService propertyImageService)
    {
        _dbContext = dbContext;
        _propertyImageService = propertyImageService;
    }

    // Get all properties
    public async Task<IEnumerable<PropertyResponseDto>> GetAllAsync()
    {
        var properties = await _dbContext.Properties
            .AsNoTracking()
            .Include(property => property.Amenities)
            .OrderByDescending(property => property.CreatedAt)
            .ToListAsync();

        return properties.Select(MapToResponseDto);
    }

    // Get one property by ID
    public async Task<PropertyResponseDto?> GetByIdAsync(Guid id)
    {
        var property = await _dbContext.Properties
            .AsNoTracking()
            .Include(property => property.Amenities)
            .FirstOrDefaultAsync(property => property.Id == id);

        return property is null
            ? null
            : MapToResponseDto(property);
    }

    // Create a new property
    public async Task<PropertyResponseDto> CreateAsync(
        Guid landlordId,
        CreatePropertyDto dto)
    {
        var property = new Property
        {
            Id = Guid.NewGuid(),
            LandlordId = landlordId,
            Title = dto.Title.Trim(),
            Description = dto.Description.Trim(),
            Address = dto.Address.Trim(),
            City = dto.City.Trim(),
            Latitude = dto.Latitude,
            Longitude = dto.Longitude,
            GooglePlaceId = NormalizeGooglePlaceId(dto.GooglePlaceId),
            MonthlyRent = dto.MonthlyRent,
            Bedrooms = dto.Bedrooms,
            Bathrooms = dto.Bathrooms,
            Area = dto.Area,
            AreaUnit = NormalizeAreaUnit(dto.Area, dto.AreaUnit),
            IsAvailable = true,
            CreatedAt = DateTimeOffset.UtcNow
        };

        foreach (var amenityName in CleanAmenities(dto.Amenities))
        {
            property.Amenities.Add(
                new PropertyAmenity
                {
                    Id = Guid.NewGuid(),
                    PropertyId = property.Id,
                    Name = amenityName
                });
        }

        _dbContext.Properties.Add(property);

        await _dbContext.SaveChangesAsync();

        return MapToResponseDto(property);
    }

    // Update an existing property
    public async Task<PropertyResponseDto?> UpdateAsync(
        Guid id,
        Guid landlordId,
        UpdatePropertyDto dto)
    {
        var property = await _dbContext.Properties
            .Include(property => property.Amenities)
            .FirstOrDefaultAsync(property =>
                property.Id == id &&
                property.LandlordId == landlordId);

        if (property is null)
        {
            return null;
        }

        // Update property information
        property.Title = dto.Title.Trim();
        property.Description = dto.Description.Trim();
        property.Address = dto.Address.Trim();
        property.City = dto.City.Trim();
        property.Latitude = dto.Latitude;
        property.Longitude = dto.Longitude;
        property.GooglePlaceId = NormalizeGooglePlaceId(dto.GooglePlaceId);
        property.MonthlyRent = dto.MonthlyRent;
        property.Bedrooms = dto.Bedrooms;
        property.Bathrooms = dto.Bathrooms;
        property.Area = dto.Area;
        property.AreaUnit = NormalizeAreaUnit(dto.Area, dto.AreaUnit);
        property.IsAvailable = dto.IsAvailable;
        property.UpdatedAt = DateTimeOffset.UtcNow;

        // Remove the existing amenities.
        _dbContext.PropertyAmenities.RemoveRange(
            property.Amenities);

        // Add the replacement amenities directly to the DbSet.
        foreach (var amenityName in CleanAmenities(dto.Amenities))
        {
            _dbContext.PropertyAmenities.Add(
                new PropertyAmenity
                {
                    Id = Guid.NewGuid(),
                    PropertyId = property.Id,
                    Name = amenityName
                });
        }

        await _dbContext.SaveChangesAsync();

        // Reload amenities so the response contains the new values.
        await _dbContext.Entry(property)
            .Collection(item => item.Amenities)
            .LoadAsync();

        return MapToResponseDto(property);
    }

    // Delete a property
    public async Task<bool> DeleteAsync(
        Guid id,
        Guid landlordId)
    {
        var property = await _dbContext.Properties
            .FirstOrDefaultAsync(property =>
                property.Id == id &&
                property.LandlordId == landlordId);

        if (property is null)
        {
            return false;
        }

        var hasRentalOffer = await _dbContext.RentalOffers
            .AnyAsync(offer => offer.PropertyId == id);
        var hasLeaseAgreement = await _dbContext.LeaseAgreements
            .AnyAsync(lease => lease.PropertyId == id);

        if (hasRentalOffer || hasLeaseAgreement)
        {
            return false;
        }

        // Delete all property images from R2 and remove
        // their database metadata before deleting the property.
        await _propertyImageService.DeleteAllForPropertyAsync(
            id,
            landlordId);

        _dbContext.Properties.Remove(property);

        await _dbContext.SaveChangesAsync();

        return true;
    }

    // Clean up amenities before storing them.
    private static IEnumerable<string> CleanAmenities(
        IEnumerable<string>? amenities)
    {
        return (amenities ?? Enumerable.Empty<string>())
            .Where(amenity => !string.IsNullOrWhiteSpace(amenity))
            .Select(amenity => amenity.Trim())
            .Distinct(StringComparer.OrdinalIgnoreCase);
    }

    private static string? NormalizeAreaUnit(decimal? area, string? areaUnit)
    {
        if (!area.HasValue)
        {
            return null;
        }

        return string.IsNullOrWhiteSpace(areaUnit)
            ? "sqft"
            : areaUnit.Trim().ToLowerInvariant();
    }

    private static string? NormalizeGooglePlaceId(string? googlePlaceId)
    {
        return string.IsNullOrWhiteSpace(googlePlaceId)
            ? null
            : googlePlaceId.Trim();
    }

    // Convert Property entity to PropertyResponseDto.
    private static PropertyResponseDto MapToResponseDto(
        Property property)
    {
        return new PropertyResponseDto
        {
            Id = property.Id,
            LandlordId = property.LandlordId,
            Title = property.Title,
            Description = property.Description,
            Address = property.Address,
            City = property.City,
            Latitude = property.Latitude,
            Longitude = property.Longitude,
            GooglePlaceId = property.GooglePlaceId,
            MonthlyRent = property.MonthlyRent,
            Bedrooms = property.Bedrooms,
            Bathrooms = property.Bathrooms,
            Area = property.Area,
            AreaUnit = property.AreaUnit,
            IsAvailable = property.IsAvailable,
            CreatedAt = property.CreatedAt,
            UpdatedAt = property.UpdatedAt,

            Amenities = property.Amenities
                .Select(amenity => amenity.Name)
                .ToList()
        };
    }
}
