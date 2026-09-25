using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using RentFlow.Api.Authorization;
using RentFlow.Api.DTOs.Auth;
using RentFlow.Api.Services;
using RentFlow.Api.Services.Interfaces;

namespace RentFlow.Api.Controllers;

[ApiController]
[Route("api/admin/maintenance-technicians")]
[Authorize(Policy = AuthorizationPolicies.ActiveAdmin)]
public sealed class AdminMaintenanceTechniciansController(
    TechnicianProvisioningService provisioningService,
    ICurrentUserService currentUserService) : ControllerBase
{
    [HttpPost]
    [ProducesResponseType<MaintenanceTechnicianProvisioningResponseDto>(
        StatusCodes.Status201Created)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status409Conflict)]
    public async Task<ActionResult<MaintenanceTechnicianProvisioningResponseDto>> Create(
        [FromBody] CreateMaintenanceTechnicianRequestDto request,
        CancellationToken cancellationToken)
    {
        if (currentUserService.UserId is not { } adminUserId)
        {
            return Forbid();
        }

        try
        {
            var response = await provisioningService.CreatePendingAsync(
                adminUserId,
                request,
                cancellationToken);
            return StatusCode(StatusCodes.Status201Created, response);
        }
        catch (TechnicianProvisioningException exception)
        {
            return MapException(exception);
        }
    }

    private ActionResult MapException(TechnicianProvisioningException exception)
    {
        var statusCode = exception.Error switch
        {
            TechnicianProvisioningError.Validation => StatusCodes.Status400BadRequest,
            TechnicianProvisioningError.DuplicateEmail => StatusCodes.Status409Conflict,
            TechnicianProvisioningError.Forbidden => StatusCodes.Status403Forbidden,
            _ => StatusCodes.Status500InternalServerError
        };
        return StatusCode(statusCode, new ProblemDetails
        {
            Status = statusCode,
            Title = "Staff provisioning failed.",
            Detail = statusCode == StatusCodes.Status500InternalServerError
                ? "The request could not be completed."
                : exception.Message
        });
    }
}
