using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using RentFlow.Api.DTOs.ViewingReviews;
using RentFlow.Api.Models;
using RentFlow.Api.Services;
using RentFlow.Api.Services.Interfaces;

namespace RentFlow.Api.Controllers;

[ApiController]
[Authorize(Roles = nameof(UserRole.Tenant))]
public sealed class ViewingReviewsController(ViewingReviewService reviews, ICurrentUserService currentUser) : ControllerBase
{
    [HttpGet("api/viewings/{viewingId:guid}/review")]
    public Task<IActionResult> GetOwn(Guid viewingId, CancellationToken ct) => Execute(async () =>
    {
        if (currentUser.UserId is not Guid tenant) return Unauthorized();
        var review = await reviews.GetOwnAsync(tenant, viewingId, ct);
        return review is null ? NoContent() : Ok(review);
    });

    [HttpPut("api/viewings/{viewingId:guid}/review")]
    public Task<IActionResult> Save(Guid viewingId, SaveViewingReviewDto input, CancellationToken ct) => Execute(async () =>
    {
        if (currentUser.UserId is not Guid tenant) return Unauthorized();
        return Ok(await reviews.SaveAsync(tenant, viewingId, input, ct));
    });

    [AllowAnonymous, HttpGet("api/properties/{propertyId:guid}/viewing-reviews")]
    public Task<IActionResult> Property(Guid propertyId, CancellationToken ct) => Execute(async () => Ok(await reviews.GetPublicAsync(propertyId, false, ct)));

    [AllowAnonymous, HttpGet("api/properties/{propertyId:guid}/landlord-viewing-reviews")]
    public Task<IActionResult> Landlord(Guid propertyId, CancellationToken ct) => Execute(async () => Ok(await reviews.GetPublicAsync(propertyId, true, ct)));

    private async Task<IActionResult> Execute(Func<Task<IActionResult>> action)
    {
        try { return await action(); }
        catch (ViewingServiceException error)
        {
            return Problem(statusCode: error.Error switch { ViewingServiceError.NotFound => 404, ViewingServiceError.Conflict => 409, _ => 400 }, detail: error.Message);
        }
    }
}
