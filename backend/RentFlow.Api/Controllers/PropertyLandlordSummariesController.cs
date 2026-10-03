using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using RentFlow.Api.DTOs;
using RentFlow.Api.Services.Interfaces;

namespace RentFlow.Api.Controllers;

[ApiController]
[AllowAnonymous]
[Route("api/properties/{propertyId:guid}/landlord-summary")]
public sealed class PropertyLandlordSummariesController(
    IPublicLandlordSummaryService landlordSummaryService) : ControllerBase
{
    [HttpGet]
    public async Task<ActionResult<PublicLandlordSummaryDto>> GetSummary(
        Guid propertyId,
        CancellationToken cancellationToken)
    {
        var summary = await landlordSummaryService.GetForPropertyAsync(
            propertyId,
            cancellationToken);

        return summary is null ? NotFound() : Ok(summary);
    }

    [HttpGet("image")]
    public async Task<IActionResult> GetImage(
        Guid propertyId,
        CancellationToken cancellationToken)
    {
        var image = await landlordSummaryService.GetImageForPropertyAsync(
            propertyId,
            cancellationToken);

        if (image is null)
        {
            return NotFound();
        }

        Response.GetTypedHeaders().CacheControl =
            new Microsoft.Net.Http.Headers.CacheControlHeaderValue
            {
                Public = true,
                MaxAge = TimeSpan.FromMinutes(5)
            };

        return File(image.Content, image.ContentType);
    }
}
