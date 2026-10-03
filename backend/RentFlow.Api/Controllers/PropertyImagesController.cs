using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using RentFlow.Api.DTOs;
using RentFlow.Api.Models;
using RentFlow.Api.Services.Interfaces;

namespace RentFlow.Api.Controllers;

[ApiController]
[Route("api/properties/{propertyId:guid}/images")]
public class PropertyImagesController : ControllerBase
{
    private readonly IPropertyImageService _propertyImageService;
    private readonly ICurrentUserService _currentUserService;

    public PropertyImagesController(
        IPropertyImageService propertyImageService,
        ICurrentUserService currentUserService)
    {
        _propertyImageService = propertyImageService;
        _currentUserService = currentUserService;
    }

    // =========================================================
    // GET ALL PROPERTY IMAGES
    // GET: api/properties/{propertyId}/images
    // =========================================================

    [HttpGet]
    [AllowAnonymous]
    public async Task<ActionResult<IReadOnlyList<PropertyImageResponseDto>>>
        GetImages(
            Guid propertyId,
            CancellationToken cancellationToken)
    {
        var images =
            await _propertyImageService.GetByPropertyAsync(
                propertyId,
                cancellationToken);

        return Ok(images);
    }

    // =========================================================
    // GET SIGNED IMAGE URL
    // GET: api/properties/{propertyId}/images/{imageId}/url
    // =========================================================

    [HttpGet("{imageId:guid}/url")]
    [AllowAnonymous]
    public async Task<ActionResult<object>> GetImageUrl(
        Guid propertyId,
        Guid imageId,
        CancellationToken cancellationToken)
    {
        var images =
            await _propertyImageService.GetByPropertyAsync(
                propertyId,
                cancellationToken);

        if (!images.Any(image => image.Id == imageId))
        {
            return NotFound();
        }

        var url =
            await _propertyImageService.GenerateImageUrlAsync(
                imageId,
                cancellationToken);

        if (url is null)
        {
            return NotFound();
        }

        return Ok(new
        {
            imageId,
            url
        });
    }

    // =========================================================
    // UPLOAD PROPERTY IMAGE
    // POST: api/properties/{propertyId}/images
    // =========================================================

    [HttpPost]
    [Authorize(Roles = nameof(UserRole.Landlord))]
    [Consumes("multipart/form-data")]
    public async Task<ActionResult<PropertyImageResponseDto>>
        UploadImage(
            Guid propertyId,
            IFormFile file,
            CancellationToken cancellationToken)
    {
        var landlordId = GetCurrentLandlordId();

        if (landlordId is null)
        {
            return Forbid();
        }

        if (file is null || file.Length <= 0)
        {
            return BadRequest(
                new
                {
                    message = "An image file is required."
                });
        }

        try
        {
            await using var stream =
                file.OpenReadStream();

            var result =
                await _propertyImageService.UploadAsync(
                    propertyId,
                    landlordId.Value,
                    stream,
                    file.FileName,
                    file.ContentType,
                    file.Length,
                    cancellationToken);

            return CreatedAtAction(
                nameof(GetImageUrl),
                new
                {
                    propertyId,
                    imageId = result.Id
                },
                result);
        }
        catch (ArgumentException exception)
        {
            return BadRequest(
                new
                {
                    message = exception.Message
                });
        }
        catch (InvalidOperationException exception)
        {
            return NotFound(
                new
                {
                    message = exception.Message
                });
        }
    }

    // =========================================================
    // DELETE PROPERTY IMAGE
    // DELETE: api/properties/{propertyId}/images/{imageId}
    // =========================================================

    [HttpDelete("{imageId:guid}")]
    [Authorize(Roles = nameof(UserRole.Landlord))]
    public async Task<IActionResult> DeleteImage(
        Guid propertyId,
        Guid imageId,
        CancellationToken cancellationToken)
    {
        var landlordId = GetCurrentLandlordId();

        if (landlordId is null)
        {
            return Forbid();
        }

        var deleted =
            await _propertyImageService.DeleteAsync(
                propertyId,
                imageId,
                landlordId.Value,
                cancellationToken);

        if (!deleted)
        {
            return NotFound();
        }

        return NoContent();
    }

    [HttpPut("{imageId:guid}/primary")]
    [Authorize(Roles = nameof(UserRole.Landlord))]
    public async Task<ActionResult<PropertyImageResponseDto>> SetPrimaryImage(
        Guid propertyId,
        Guid imageId,
        CancellationToken cancellationToken)
    {
        var landlordId = GetCurrentLandlordId();
        if (landlordId is null)
        {
            return Forbid();
        }

        var image = await _propertyImageService.SetPrimaryAsync(
            propertyId,
            imageId,
            landlordId.Value,
            cancellationToken);

        return image is null ? NotFound() : Ok(image);
    }

    [HttpPut("order")]
    [Authorize(Roles = nameof(UserRole.Landlord))]
    public async Task<ActionResult<IReadOnlyList<PropertyImageResponseDto>>> ReorderImages(
        Guid propertyId,
        [FromBody] ReorderPropertyImagesDto request,
        CancellationToken cancellationToken)
    {
        var landlordId = GetCurrentLandlordId();
        if (landlordId is null)
        {
            return Forbid();
        }

        try
        {
            var images = await _propertyImageService.ReorderAsync(
                propertyId,
                landlordId.Value,
                request.ImageIds,
                cancellationToken);

            return images is null ? NotFound() : Ok(images);
        }
        catch (ArgumentException exception)
        {
            return BadRequest(new { message = exception.Message });
        }
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
}
