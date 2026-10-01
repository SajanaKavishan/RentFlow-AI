using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using RentFlow.Api.Models;
using RentFlow.Api.Services.Interfaces;

namespace RentFlow.Api.Controllers;

[ApiController]
[Route("api/tenant/property-favorites")]
[Authorize(Roles = nameof(UserRole.Tenant))]
public sealed class TenantPropertyFavoritesController(
    ITenantPropertyFavoriteService favoriteService,
    ICurrentUserService currentUserService) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> Get(CancellationToken cancellationToken)
    {
        if (currentUserService.UserId is not Guid tenantId)
        {
            return Unauthorized(new { message = "Authenticated tenant ID was not found." });
        }

        return Ok(await favoriteService.GetAsync(tenantId, cancellationToken));
    }

    [HttpPut("{propertyId:guid}")]
    public async Task<IActionResult> Add(
        Guid propertyId,
        CancellationToken cancellationToken)
    {
        if (currentUserService.UserId is not Guid tenantId)
        {
            return Unauthorized(new { message = "Authenticated tenant ID was not found." });
        }

        return await favoriteService.AddAsync(tenantId, propertyId, cancellationToken)
            ? NoContent()
            : NotFound(new { message = "The available property was not found." });
    }

    [HttpDelete("{propertyId:guid}")]
    public async Task<IActionResult> Remove(
        Guid propertyId,
        CancellationToken cancellationToken)
    {
        if (currentUserService.UserId is not Guid tenantId)
        {
            return Unauthorized(new { message = "Authenticated tenant ID was not found." });
        }

        await favoriteService.RemoveAsync(tenantId, propertyId, cancellationToken);
        return NoContent();
    }
}
