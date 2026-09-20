using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using RentFlow.Api.Services.Interfaces;

namespace RentFlow.Api.Controllers;

[ApiController]
[Route("api/notifications")]
[Authorize]
public sealed class NotificationsController(
    INotificationService notificationService,
    ICurrentUserService currentUserService) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> GetPage(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20,
        CancellationToken cancellationToken = default)
    {
        if (currentUserService.UserId is not Guid recipientId)
        {
            return Unauthorized(new { message = "Authenticated user ID was not found." });
        }

        if (page < 1 || pageSize is < 1 or > 100)
        {
            return BadRequest(new { message = "Page must be at least 1 and pageSize must be between 1 and 100." });
        }

        var response = await notificationService.GetPageAsync(
            recipientId,
            page,
            pageSize,
            cancellationToken);

        return Ok(response);
    }

    [HttpGet("unread-count")]
    public async Task<IActionResult> GetUnreadCount(CancellationToken cancellationToken)
    {
        if (currentUserService.UserId is not Guid recipientId)
        {
            return Unauthorized(new { message = "Authenticated user ID was not found." });
        }

        return Ok(await notificationService.GetUnreadCountAsync(recipientId, cancellationToken));
    }

    [HttpPatch("{id:guid}/read")]
    public async Task<IActionResult> MarkAsRead(
        Guid id,
        CancellationToken cancellationToken)
    {
        if (currentUserService.UserId is not Guid recipientId)
        {
            return Unauthorized(new { message = "Authenticated user ID was not found." });
        }

        var notification = await notificationService.MarkAsReadAsync(
            recipientId,
            id,
            cancellationToken);

        return notification is null
            ? NotFound(new { message = "Notification was not found." })
            : Ok(notification);
    }
}