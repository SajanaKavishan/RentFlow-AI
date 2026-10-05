using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using RentFlow.Api.DTOs.ViewingFollowUps;
using RentFlow.Api.Models;
using RentFlow.Api.Services;
using RentFlow.Api.Services.Interfaces;

namespace RentFlow.Api.Controllers;

[ApiController]
[Route("api/viewing-follow-ups")]
[Authorize(Roles = nameof(UserRole.Tenant))]
public sealed class ViewingFollowUpsController(IViewingFollowUpService followUps, ICurrentUserService currentUser) : ControllerBase
{
    [HttpPost("next/claim")]
    [ProducesResponseType<ViewingFollowUpDto>(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    public async Task<IActionResult> Claim(CancellationToken cancellationToken)
    {
        if (currentUser.UserId is not Guid tenantId) return Unauthorized();
        var result = await followUps.ClaimNextAsync(tenantId, cancellationToken);
        return result is null ? NoContent() : Ok(result);
    }

    [HttpPost("{followUpId:guid}/respond")]
    [ProducesResponseType<ViewingFollowUpResponseDto>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status409Conflict)]
    public async Task<IActionResult> Respond(Guid followUpId, RespondViewingFollowUpDto request, CancellationToken cancellationToken)
    {
        if (currentUser.UserId is not Guid tenantId) return Unauthorized();
        if (!Enum.TryParse<ViewingFollowUpDecision>(request.Decision, out var decision) || !Enum.IsDefined(decision)
            || decision.ToString() != request.Decision)
            return Problem(statusCode: StatusCodes.Status400BadRequest, detail: "Select ApplyNow or NotNow.");
        try { return Ok(await followUps.RespondAsync(tenantId, followUpId, decision, cancellationToken)); }
        catch (RentalApplicationServiceException error)
        {
            var status = error.Error switch { RentalApplicationServiceError.NotFound => 404,
                RentalApplicationServiceError.Conflict => 409, _ => 400 };
            return Problem(statusCode: status, detail: error.Message);
        }
    }
}
