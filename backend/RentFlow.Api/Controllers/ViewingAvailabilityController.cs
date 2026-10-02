using System.Globalization;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using RentFlow.Api.DTOs.Viewings;
using RentFlow.Api.Models;
using RentFlow.Api.Services;
using RentFlow.Api.Services.Interfaces;

namespace RentFlow.Api.Controllers;

[ApiController]
[Route("api/properties/{propertyId:guid}")]
[Authorize]
public sealed class ViewingAvailabilityController(ViewingAvailabilityService service,
    IPropertyAccessGuard access, ICurrentUserService user) : ControllerBase
{
    [HttpGet("viewing-availability")]
    [Authorize(Roles = "Landlord,Admin")]
    public Task<ActionResult<ViewingAvailabilityDto>> Get(Guid propertyId, CancellationToken ct) =>
        Execute(async () => { await EnsureOwner(propertyId, ct); return await service.GetAsync(propertyId, ct); });

    [HttpPut("viewing-availability")]
    [Authorize(Roles = "Landlord,Admin")]
    public Task<ActionResult<ViewingAvailabilityDto>> Put(Guid propertyId,
        [FromBody] ViewingAvailabilityDto request, CancellationToken ct) =>
        Execute(async () =>
        {
            await EnsureOwner(propertyId, ct);
            return await service.SaveAsync(propertyId, user.Role == UserRole.Admin ? null : user.UserId, request, ct);
        });

    [HttpGet("viewing-slots")]
    [Authorize(Roles = "Tenant")]
    public Task<ActionResult<ViewingSlotsDto>> Slots(Guid propertyId, [FromQuery] string? date, CancellationToken ct,
        [FromQuery] bool includeUnavailable = false) =>
        Execute(async () =>
        {
            if (!DateOnly.TryParseExact(date, "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var parsed)
                || parsed == DateOnly.MaxValue)
                throw ViewingServiceException.Validation("Date must be a calendar date in YYYY-MM-DD format.");
            return await service.GetSlotsAsync(propertyId, parsed, ct, includeUnavailable);
        });

    private async Task EnsureOwner(Guid propertyId, CancellationToken ct)
    {
        if (user.Role != UserRole.Admin && (user.UserId is null
            || !await access.CanAccessPropertyAsync(user.UserId.Value, propertyId, ct)))
            throw ViewingServiceException.NotFound("The property was not found.");
    }

    private async Task<ActionResult<T>> Execute<T>(Func<Task<T>> operation)
    {
        try { return Ok(await operation()); }
        catch (ViewingServiceException error)
        {
            var code = error.Error switch
            {
                ViewingServiceError.NotFound => 404,
                ViewingServiceError.Conflict => 409,
                _ => 400
            };
            return Problem(statusCode: code, title: "Viewing availability request failed.", detail: error.Message);
        }
    }
}
