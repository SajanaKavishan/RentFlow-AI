using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using RentFlow.Api.DTOs.ViewingReviews;
using RentFlow.Api.Models;
using RentFlow.Api.Services;
using RentFlow.Api.Services.Interfaces;

namespace RentFlow.Api.Controllers;

[ApiController]
[Authorize(Roles = nameof(UserRole.Landlord))]
[Route("api/landlord/viewing-reviews")]
public sealed class LandlordViewingReviewsController(ViewingReviewService reviews, ICurrentUserService currentUser) : ControllerBase
{
    [HttpGet("summary")]
    public async Task<ActionResult<LandlordViewingReviewSummaryDto>> Get(CancellationToken cancellationToken)
    {
        if (currentUser.UserId is not Guid landlord) return Unauthorized();
        return Ok(await reviews.GetLandlordSummaryAsync(landlord, cancellationToken));
    }

    [HttpGet("properties/{propertyId:guid}")]
    public async Task<ActionResult<ViewingReviewSummaryDto>> GetProperty(Guid propertyId, CancellationToken cancellationToken)
    {
        if (currentUser.UserId is not Guid landlord) return Unauthorized();
        try { return Ok(await reviews.GetLandlordPropertyReviewsAsync(landlord, propertyId, cancellationToken)); }
        catch (ViewingServiceException error) when (error.Error == ViewingServiceError.NotFound) { return NotFound(); }
    }
}
