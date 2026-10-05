using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using RentFlow.Api.Data;
using RentFlow.Api.DTOs;
using RentFlow.Api.DTOs.PropertyMatching;
using RentFlow.Api.Models;
using RentFlow.Api.Services;
using RentFlow.Api.Services.Interfaces;

namespace RentFlow.Api.Controllers;

[ApiController]
[Route("api/properties")]
public class PropertiesController : ControllerBase
{
    private readonly ApplicationDbContext _context;
    private readonly IPropertyService _propertyService;
    private readonly ICurrentUserService _currentUserService;
    private readonly IPropertyMatchingOrchestrator _propertyMatchingOrchestrator;

    public PropertiesController(
        ApplicationDbContext context,
        IPropertyService propertyService,
        ICurrentUserService currentUserService,
        IPropertyMatchingOrchestrator propertyMatchingOrchestrator)
    {
        _context = context;
        _propertyService = propertyService;
        _currentUserService = currentUserService;
        _propertyMatchingOrchestrator = propertyMatchingOrchestrator;
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

        if (!string.IsNullOrWhiteSpace(search))
        {
            var searchTerm = search.Trim().ToLower();

            query = query.Where(property =>
                property.Title.ToLower().Contains(searchTerm) ||
                property.Description.ToLower().Contains(searchTerm) ||
                property.Address.ToLower().Contains(searchTerm) ||
                property.City.ToLower().Contains(searchTerm));
        }

        if (!string.IsNullOrWhiteSpace(city))
        {
            var cityFilter = city.Trim().ToLower();

            query = query.Where(property =>
                property.City.ToLower() == cityFilter);
        }

        if (minRent.HasValue)
        {
            query = query.Where(property =>
                property.MonthlyRent >= minRent.Value);
        }

        if (maxRent.HasValue)
        {
            query = query.Where(property =>
                property.MonthlyRent <= maxRent.Value);
        }

        if (bedrooms.HasValue)
        {
            query = query.Where(property =>
                property.Bedrooms == bedrooms.Value);
        }

        if (bathrooms.HasValue)
        {
            query = query.Where(property =>
                property.Bathrooms == bathrooms.Value);
        }

        if (isAvailable.HasValue)
        {
            query = query.Where(property =>
                property.IsAvailable == isAvailable.Value);
        }

        var properties = await query
            .OrderByDescending(property => property.CreatedAt)
            .ToListAsync();

        if (!string.IsNullOrWhiteSpace(amenity))
        {
            var amenityFilter = PropertyListingCatalog.NormalizeForMatching(amenity);
            properties = properties
                .Where(property => property.Amenities.Any(item =>
                    string.Equals(
                        item.CanonicalKey ?? PropertyListingCatalog.NormalizeForMatching(item.Name),
                        amenityFilter,
                        StringComparison.OrdinalIgnoreCase)))
                .ToList();
        }

        var result = properties
            .Select(MapToResponseDto)
            .ToList();

        return Ok(result);
    }

    // =========================================================
    // GET /api/properties/mine
    // Logged-in landlord's own properties only
    // =========================================================

    [HttpGet("mine")]
    [Authorize(Roles = nameof(UserRole.Landlord))]
    public async Task<ActionResult<IEnumerable<PropertyResponseDto>>>
        GetMyProperties()
    {
        var landlordId = GetCurrentLandlordId();

        if (landlordId is null)
        {
            return Forbid();
        }

        var properties = await _context.Properties
            .AsNoTracking()
            .Include(property => property.Amenities)
            .Where(property =>
                property.LandlordId == landlordId.Value)
            .OrderByDescending(property => property.CreatedAt)
            .ToListAsync();

        var result = properties
            .Select(MapToResponseDto)
            .ToList();

        return Ok(result);
    }

    [HttpGet("tenant/mine")]
    [Authorize(Roles = nameof(UserRole.Tenant))]
    [ProducesResponseType<IEnumerable<PropertyResponseDto>>(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    public async Task<ActionResult<IEnumerable<PropertyResponseDto>>>
        GetMyTenantProperties(CancellationToken cancellationToken)
    {
        if (!_currentUserService.IsAuthenticated
            || _currentUserService.Role != UserRole.Tenant
            || _currentUserService.UserId is not { } tenantId
            || tenantId == Guid.Empty)
        {
            return Forbid();
        }

        var today = DateOnly.FromDateTime(DateTime.UtcNow);
        var properties = await TenantMaintenanceEligibility.EligibleProperties(_context, tenantId, today)
            .AsNoTracking()
            .Include(property => property.Amenities)
            .OrderByDescending(property => property.CreatedAt)
            .ToListAsync(cancellationToken);

        return Ok(properties.Select(MapToResponseDto).ToList());
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

    // Atomic, presence-safe endpoint for the current Add/Edit listing workflow.
    [HttpPut("{id:guid}/listing")]
    [Authorize(Roles = nameof(UserRole.Landlord))]
    public async Task<ActionResult<PropertyResponseDto>> UpdatePropertyListing(
        Guid id,
        UpdatePropertyListingDto dto)
    {
        var landlordId = GetCurrentLandlordId();
        if (landlordId is null) return Forbid();

        var property = await _propertyService.UpdateListingAsync(
            id, landlordId.Value, dto);

        return property is null ? NotFound() : Ok(property);
    }

    // =========================================================
    // POST /api/properties/match
    // Deterministic matching with optional advisory explanation
    // =========================================================

    [HttpPost("match")]
    [Authorize(Roles = nameof(UserRole.Tenant))]
    public async Task<ActionResult<PropertyMatchingResponse>>
        MatchProperties(
            [FromBody] PropertyMatchingRequest request,
            CancellationToken cancellationToken)
    {
        var result =
            await _propertyMatchingOrchestrator.MatchAsync(
                request,
                cancellationToken);

        return Ok(result);
    }

    [HttpGet("matches")]
    [Authorize(Roles = nameof(UserRole.Tenant))]
    public async Task<ActionResult<PropertyMatchingResponse>>
        GetSavedPreferenceMatches(
            [FromServices] ITenantPropertyPreferenceService preferenceService,
            CancellationToken cancellationToken)
    {
        if (_currentUserService.UserId is not Guid tenantId)
        {
            return Unauthorized(new { message = "Authenticated tenant ID was not found." });
        }

        var saved = await preferenceService.GetAsync(tenantId, cancellationToken);
        if (!saved.IsConfigured)
        {
            return BadRequest(new { message = "Set match preferences before requesting matches." });
        }

        var result = await _propertyMatchingOrchestrator.MatchAsync(
            new PropertyMatchingRequest
            {
                PreferredCity = saved.PreferredCity,
                MaximumMonthlyRent = saved.MaximumMonthlyRent,
                MinimumBedrooms = saved.MinimumBedrooms,
                MinimumBathrooms = saved.MinimumBathrooms,
                PreferredAmenities = saved.PreferredAmenities
            },
            cancellationToken);

        return Ok(result);
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
            Latitude = property.Latitude,
            Longitude = property.Longitude,
            GooglePlaceId = property.GooglePlaceId,
            MonthlyRent = property.MonthlyRent,
            AdvertisedSecurityDeposit = property.AdvertisedSecurityDeposit,
            PreferredLeaseTermMonths = property.PreferredLeaseTermMonths,
            PetPolicy = property.PetPolicy,
            PetPolicyNotes = property.PetPolicyNotes,
            IncludedUtilities = property.IncludedUtilities?.ToList(),
            Bedrooms = property.Bedrooms,
            Bathrooms = property.Bathrooms,
            Area = property.Area,
            AreaUnit = property.AreaUnit,
            AreaType = property.AreaType,
            AvailableFrom = property.AvailableFrom,
            IsAvailable = property.IsAvailable,
            CreatedAt = property.CreatedAt,
            UpdatedAt = property.UpdatedAt,

            Amenities = property.Amenities
                .Select(amenity => amenity.Name)
                .ToList(),
            AmenityDetails = property.Amenities
                .Select(amenity => new PropertyAmenityResponseDto
                {
                    CanonicalKey = amenity.CanonicalKey,
                    Name = amenity.Name
                })
                .ToList()
        };
    }
}
