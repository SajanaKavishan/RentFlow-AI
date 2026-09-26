using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using RentFlow.Api.DTOs.SupportTickets;
using RentFlow.Api.Models;
using RentFlow.Api.Services.Interfaces;

namespace RentFlow.Api.Controllers;

[ApiController]
[Route("api/support-tickets")]
[Authorize]
public sealed class SupportTicketsController(
    ISupportTicketService supportTicketService,
    ICurrentUserService currentUserService) : ControllerBase
{
    [HttpPost]
    public async Task<IActionResult> Create(
        CreateSupportTicketRequestDto request,
        CancellationToken cancellationToken)
    {
        if (currentUserService.UserId is not Guid userId)
        {
            return Unauthorized(new { message = "Authenticated user ID was not found." });
        }

        if (!Enum.TryParse<SupportTicketCategory>(request.Category, ignoreCase: false, out var category)
            || !Enum.IsDefined(category)
            || request.Category != category.ToString())
        {
            ModelState.AddModelError(nameof(request.Category), "Select a supported support category.");
        }

        var subject = request.Subject.Trim();
        var message = request.Message.Trim();
        if (subject.Length == 0)
        {
            ModelState.AddModelError(nameof(request.Subject), "Subject cannot be empty or whitespace.");
        }

        if (message.Length == 0)
        {
            ModelState.AddModelError(nameof(request.Message), "Message cannot be empty or whitespace.");
        }

        if (!ModelState.IsValid)
        {
            return ValidationProblem(ModelState);
        }

        var response = await supportTicketService.CreateAsync(
            userId,
            category,
            subject,
            message,
            cancellationToken);

        return Created("/api/support-tickets/mine", response);
    }

    [HttpGet("mine")]
    public async Task<IActionResult> GetMine(CancellationToken cancellationToken)
    {
        if (currentUserService.UserId is not Guid userId)
        {
            return Unauthorized(new { message = "Authenticated user ID was not found." });
        }

        return Ok(await supportTicketService.GetMineAsync(userId, cancellationToken));
    }
}
