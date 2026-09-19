using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using RentFlow.Api.Data;
using RentFlow.Api.DTOs;
using RentFlow.Api.Models;
using RentFlow.Api.Services.Interfaces;

namespace RentFlow.Api.Controllers;

[ApiController]
[Route("api/properties")]
public class PropertiesController : ControllerBase
{
    private readonly ApplicationDbContext _context;
    private readonly IPropertyService _propertyService;
    private readonly ICurrentUserService _currentUserService;

    public PropertiesController(
        ApplicationDbContext context,
        IPropertyService propertyService,
        ICurrentUserService currentUserService)
    {
        _context = context;
        _propertyService = propertyService;
        _currentUserService = currentUserService;
    }

    // =========================================================
    // GET /api/properties
    // Public property search and filtering
    // =========================================================

    [HttpGet]
    [AllowAnonymous]
    public async Task<ActionResult<IEnumerable<PropertyResponseDto>>>
        GetProperties(
            [FromQuery] string? search,
            [FromQuery] string? city,
            [FromQuery] decimal? minRent,
            [FromQuery] decimal? maxRent,
            [FromQuery] int? bedrooms,
            [FromQuery] int? bathrooms,
            [FromQuery] bool? isAvailable,
            [FromQuery] string? amenity)
    {
        var query = _context.Properties
            .AsNoTracking()
            .Include(property => property.Amenities)
            .AsQueryable();

        // General text/location search.
        // Searches title, description, address and city.
        if (!string.IsNullOrWhiteSpace(search))
        {
            var searchTerm = search.Trim().ToLower();

            query = query.Where(property =>
                property.Title.ToLower().Contains(searchTerm) ||
                property.Description.ToLower().Contains(searchTerm) ||
                property.Address.ToLower().Contains(searchTerm) ||
                property.City.ToLower().Contains(searchTerm));
        }

        // Exact city filter.
        if (!string.IsNullOrWhiteSpace(city))
        {
            var cityFilter = city.Trim().ToLower();

            query = query.Where(property =>
                property.City.ToLower() == cityFilter);
        }

        // Minimum monthly rent.
        if (minRent.HasValue)
        {
            query = query.Where(property =>
                property.MonthlyRent >= minRent.Value);
        }

        // Maximum monthly rent.
        if (maxRent.HasValue)
        {
            query = query.Where(property =>
                property.MonthlyRent <= maxRent.Value);
        }

        // Exact bedroom count.
        if (bedrooms.HasValue)
        {
            query = query.Where(property =>
                property.Bedrooms == bedrooms.Value);
        }

        // Exact bathroom count.
        if (bathrooms.HasValue)
        {
            query = query.Where(property =>
                property.Bathrooms == bathrooms.Value);
        }

        // Availability filter.
        if (isAvailable.HasValue)
        {
            query = query.Where(property =>
                property.IsAvailable == isAvailable.Value);
        }

        // Amenity filter.
        if (!string.IsNullOrWhiteSpace(amenity))
        {
            var amenityFilter = amenity.Trim().ToLower();

            query = query.Where(property =>
                property.Amenities.Any(item =>
                    item.Name.ToLower() == amenityFilter));
        }

        var properties = await query
            .OrderByDescending(property => property.CreatedAt)
            .ToListAsync();

        var result = properties
            .Select(MapToResponseDto)
            .ToList();

        return Ok(result);
    }

    // =========================================================
    // GET /api/properties/{id}
    // Public property details
    // =========================================================

    [HttpGet("{id:guid}")]
    [AllowAnonymous]
    public async Task<ActionResult<PropertyResponseDto>>
        GetProperty(Guid id)
    {
        var property =
            await _propertyService.GetByIdAsync(id);

        if (property is null)
        {
            return NotFound();
        }

        return Ok(property);
    }

    // =========================================================
    // POST /api/properties
    // Landlord only
    // =========================================================

    [HttpPost]
    [Authorize(Roles = nameof(UserRole.Landlord))]
    public async Task<ActionResult<PropertyResponseDto>>
        CreateProperty(CreatePropertyDto dto)
    {
        var landlordId = GetCurrentLandlordId();

        if (landlordId is null)
        {
            return Forbid();
        }

        var property =
            await _propertyService.CreateAsync(
                landlordId.Value,
                dto);

        return CreatedAtAction(
            nameof(GetProperty),
            new { id = property.Id },
            property);
    }

    // =========================================================
    // PUT /api/properties/{id}
    // Only owning landlord
    // =========================================================

    [HttpPut("{id:guid}")]
    [Authorize(Roles = nameof(UserRole.Landlord))]
    public async Task<ActionResult<PropertyResponseDto>>
        UpdateProperty(
            Guid id,
            UpdatePropertyDto dto)
    {
        var landlordId = GetCurrentLandlordId();

        if (landlordId is null)
        {
            return Forbid();
        }

        var property =
            await _propertyService.UpdateAsync(
                id,
                landlordId.Value,
                dto);

        if (property is null)
        {
            return NotFound();
        }

        return Ok(property);
    }

    // =========================================================
    // DELETE /api/properties/{id}
    // Only owning landlord
    // =========================================================

    [HttpDelete("{id:guid}")]
    [Authorize(Roles = nameof(UserRole.Landlord))]
    public async Task<IActionResult>
        DeleteProperty(Guid id)
    {
        var landlordId = GetCurrentLandlordId();

        if (landlordId is null)
        {
            return Forbid();
        }

        var deleted =
            await _propertyService.DeleteAsync(
                id,
                landlordId.Value);

        if (!deleted)
        {
            return NotFound();
        }

        return NoContent();
    }

    // =========================================================
    // AUTHENTICATED LANDLORD
    // =========================================================

    private Guid? GetCurrentLandlordId()
    {
        if (!_currentUserService.IsAuthenticated)
        {
            return null;
        }

        if (_currentUserService.Role != UserRole.Landlord)
        {
            return null;
        }

        var userId = _currentUserService.UserId;

        if (!userId.HasValue ||
            userId.Value == Guid.Empty)
        {
            return null;
        }

        return userId.Value;
    }

    // =========================================================
    // MAPPING
    // =========================================================

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
            MonthlyRent = property.MonthlyRent,
            Bedrooms = property.Bedrooms,
            Bathrooms = property.Bathrooms,
            IsAvailable = property.IsAvailable,
            CreatedAt = property.CreatedAt,
            UpdatedAt = property.UpdatedAt,

            Amenities = property.Amenities
                .Select(amenity => amenity.Name)
                .ToList()
        };
    }
}