using Microsoft.EntityFrameworkCore;
using RentFlow.Api.Data;
using RentFlow.Api.DTOs;
using RentFlow.Api.Models;
using RentFlow.Api.Services.Interfaces;

namespace RentFlow.Api.Services;

public class PropertyService : IPropertyService
{
    private readonly ApplicationDbContext _dbContext;

    public PropertyService(ApplicationDbContext dbContext)
    {
        _dbContext = dbContext;
    }

    // Get all properties
    public async Task<IEnumerable<PropertyResponseDto>> GetAllAsync()
    {
        return await _dbContext.Properties
            .AsNoTracking()
            .Select(property => new PropertyResponseDto
            {
                Id = property.Id,
                LandlordId = property.LandlordId,
                Title = property.Title,
                Description = property.Description,
                Address = property.Address,
                City = property.City,
                MonthlyRent = property.MonthlyRent,
                Bedrooms = property.Bedrooms,
                Bathrooms = property.Bathrooms,
                IsAvailable = property.IsAvailable,
                CreatedAt = property.CreatedAt,
                UpdatedAt = property.UpdatedAt
            })
            .ToListAsync();
    }

    // Get one property by ID
    public async Task<PropertyResponseDto?> GetByIdAsync(Guid id)
    {
        return await _dbContext.Properties
            .AsNoTracking()
            .Where(property => property.Id == id)
            .Select(property => new PropertyResponseDto
            {
                Id = property.Id,
                LandlordId = property.LandlordId,
                Title = property.Title,
                Description = property.Description,
                Address = property.Address,
                City = property.City,
                MonthlyRent = property.MonthlyRent,
                Bedrooms = property.Bedrooms,
                Bathrooms = property.Bathrooms,
                IsAvailable = property.IsAvailable,
                CreatedAt = property.CreatedAt,
                UpdatedAt = property.UpdatedAt
            })
            .FirstOrDefaultAsync();
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
            Title = dto.Title,
            Description = dto.Description,
            Address = dto.Address,
            City = dto.City,
            MonthlyRent = dto.MonthlyRent,
            Bedrooms = dto.Bedrooms,
            Bathrooms = dto.Bathrooms,
            IsAvailable = true,
            CreatedAt = DateTimeOffset.UtcNow
        };

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
            .FirstOrDefaultAsync(property =>
                property.Id == id &&
                property.LandlordId == landlordId);

        if (property is null)
        {
            return null;
        }

        property.Title = dto.Title;
        property.Description = dto.Description;
        property.Address = dto.Address;
        property.City = dto.City;
        property.MonthlyRent = dto.MonthlyRent;
        property.Bedrooms = dto.Bedrooms;
        property.Bathrooms = dto.Bathrooms;
        property.IsAvailable = dto.IsAvailable;
        property.UpdatedAt = DateTimeOffset.UtcNow;

        await _dbContext.SaveChangesAsync();

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

        _dbContext.Properties.Remove(property);
        await _dbContext.SaveChangesAsync();

        return true;
    }

    // Convert Property entity to PropertyResponseDto
    private static PropertyResponseDto MapToResponseDto(Property property)
    {
        return new PropertyResponseDto
        {
            Id = property.Id,
            LandlordId = property.LandlordId,
            Title = property.Title,
            Description = property.Description,
            Address = property.Address,
            City = property.City,
            MonthlyRent = property.MonthlyRent,
            Bedrooms = property.Bedrooms,
            Bathrooms = property.Bathrooms,
            IsAvailable = property.IsAvailable,
            CreatedAt = property.CreatedAt,
            UpdatedAt = property.UpdatedAt
        };
    }
}