using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using RentFlow.Api.DTOs.Notifications;
using RentFlow.Api.Services.Interfaces;

namespace RentFlow.Api.Controllers;

[ApiController]
[Route("api/notification-preferences")]
[Authorize]
public sealed class NotificationPreferencesController(
    INotificationPreferenceService notificationPreferenceService,
    ICurrentUserService currentUserService) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> Get(CancellationToken cancellationToken)
    {
        if (currentUserService.UserId is not Guid userId)
        {
            return Unauthorized(new { message = "Authenticated user ID was not found." });
        }

        return Ok(await notificationPreferenceService.GetAsync(userId, cancellationToken));
    }

    [HttpPut]
    public async Task<IActionResult> Update(
        UpdateNotificationPreferencesRequestDto request,
        CancellationToken cancellationToken)
    {
        if (currentUserService.UserId is not Guid userId)
        {
            return Unauthorized(new { message = "Authenticated user ID was not found." });
        }

        if (!request.AccountSecurityUpdatesEnabled)
        {
            return BadRequest(new
            {
                message = "Account and security notifications are required and cannot be disabled."
            });
        }

        var response = await notificationPreferenceService.UpdateAsync(
            userId,
            request,
            cancellationToken);

        return response is null
            ? NotFound(new { message = "The authenticated user was not found." })
            : Ok(response);
    }
}
