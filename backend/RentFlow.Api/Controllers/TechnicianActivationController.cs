using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using RentFlow.Api.DTOs.Auth;
using RentFlow.Api.Services;

namespace RentFlow.Api.Controllers;

[ApiController]
[Route("api/auth/maintenance-technicians")]
public sealed class TechnicianActivationController(
    TechnicianProvisioningService provisioningService) : ControllerBase
{
    [AllowAnonymous]
    [HttpPost("activate")]
    [EnableRateLimiting("technician-activation")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status429TooManyRequests)]
    public async Task<IActionResult> Activate(
        [FromBody] ActivateMaintenanceTechnicianRequestDto request,
        CancellationToken cancellationToken)
    {
        try
        {
            await provisioningService.ActivateAsync(request, cancellationToken);
            return NoContent();
        }
        catch (TechnicianProvisioningException exception)
        {
            var statusCode = exception.Error == TechnicianProvisioningError.Persistence
                ? StatusCodes.Status500InternalServerError
                : StatusCodes.Status400BadRequest;
            return StatusCode(statusCode, new ProblemDetails
            {
                Status = statusCode,
                Title = "Technician activation failed.",
                Detail = statusCode == StatusCodes.Status500InternalServerError
                    ? "The request could not be completed."
                    : exception.Message
            });
        }
    }
}
