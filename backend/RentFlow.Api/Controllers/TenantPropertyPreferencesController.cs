using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using RentFlow.Api.DTOs.PropertyMatching;
using RentFlow.Api.Models;
using RentFlow.Api.Services.Interfaces;

namespace RentFlow.Api.Controllers;

[ApiController]
[Route("api/tenant/property-preferences")]
[Authorize(Roles = nameof(UserRole.Tenant))]
public sealed class TenantPropertyPreferencesController(
    ITenantPropertyPreferenceService preferenceService,
    ICurrentUserService currentUserService) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> Get(CancellationToken cancellationToken)
    {
        if (currentUserService.UserId is not Guid userId)
        {
            return Unauthorized(new { message = "Authenticated tenant ID was not found." });
        }

        return Ok(await preferenceService.GetAsync(userId, cancellationToken));
    }

    [HttpPut]
    public async Task<IActionResult> Update(
        UpdateTenantPropertyPreferenceRequest request,
        CancellationToken cancellationToken)
    {
        if (currentUserService.UserId is not Guid userId)
        {
            return Unauthorized(new { message = "Authenticated tenant ID was not found." });
        }

        var normalizedAmenities = (request.PreferredAmenities ?? [])
            .Where(item => !string.IsNullOrWhiteSpace(item))
            .Select(item => item.Trim())
            .ToList();

        if (normalizedAmenities.Any(item => item.Length > 100))
        {
            ModelState.AddModelError(
                nameof(request.PreferredAmenities),
                "Each preferred amenity must be 100 characters or fewer.");
            return ValidationProblem(ModelState);
        }

        var hasAnyPreference = !string.IsNullOrWhiteSpace(request.PreferredCity)
            || request.MaximumMonthlyRent.HasValue
            || request.MinimumBedrooms.HasValue
            || request.MinimumBathrooms.HasValue
            || normalizedAmenities.Count > 0;

        if (!hasAnyPreference)
        {
            ModelState.AddModelError(string.Empty, "Set at least one match preference.");
            return ValidationProblem(ModelState);
        }

        var normalizedRequest = new UpdateTenantPropertyPreferenceRequest
        {
            PreferredCity = request.PreferredCity,
            MaximumMonthlyRent = request.MaximumMonthlyRent,
            MinimumBedrooms = request.MinimumBedrooms,
            MinimumBathrooms = request.MinimumBathrooms,
            PreferredAmenities = normalizedAmenities
        };

        var result = await preferenceService.UpdateAsync(
            userId,
            normalizedRequest,
            cancellationToken);

        return result is null
            ? NotFound(new { message = "The authenticated tenant was not found." })
            : Ok(result);
    }

    [HttpDelete]
    public async Task<IActionResult> Delete(CancellationToken cancellationToken)
    {
        if (currentUserService.UserId is not Guid userId)
        {
            return Unauthorized(new { message = "Authenticated tenant ID was not found." });
        }

        await preferenceService.DeleteAsync(userId, cancellationToken);
        return NoContent();
    }
}
