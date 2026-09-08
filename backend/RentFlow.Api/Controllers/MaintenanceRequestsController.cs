using Microsoft.AspNetCore.Mvc;
using RentFlow.Api.DTOs.Maintenance;
using RentFlow.Api.Services;
using RentFlow.Api.Services.Interfaces;

namespace RentFlow.Api.Controllers;

/// <summary>
/// Handles HTTP requests for maintenance requests.
/// </summary>
[ApiController]
[Route("api/maintenance-requests")]
public class MaintenanceRequestsController(
    IMaintenanceRequestService maintenanceRequestService,
    ILogger<MaintenanceRequestsController> logger) : ControllerBase
{
    [HttpPost]
    [ProducesResponseType<MaintenanceRequestResponseDto>(StatusCodes.Status201Created)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
    public Task<ActionResult<MaintenanceRequestResponseDto>> Create(
        [FromQuery] Guid tenantId,
        [FromBody] CreateMaintenanceRequestDto request,
        CancellationToken cancellationToken)
    {
        // TODO: Replace tenantId with the authenticated user's tenant claim.
        return ExecuteAsync(
            () => maintenanceRequestService.CreateAsync(tenantId, request, cancellationToken),
            result => CreatedAtAction(nameof(GetById), new { id = result.Id }, result));
    }

    [HttpGet("{id:guid}")]
    [ProducesResponseType<MaintenanceRequestResponseDto>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    public Task<ActionResult<MaintenanceRequestResponseDto>> GetById(
        Guid id,
        CancellationToken cancellationToken)
    {
        return ExecuteAsync(
            () => GetRequiredRequestAsync(id, cancellationToken),
            result => Ok(result));
    }

    [HttpGet("tenant/{tenantId:guid}")]
    [ProducesResponseType<IReadOnlyList<MaintenanceRequestSummaryDto>>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
    public Task<ActionResult<IReadOnlyList<MaintenanceRequestSummaryDto>>> GetByTenant(
        Guid tenantId,
        CancellationToken cancellationToken)
    {
        // TODO: Authorize tenantId against the authenticated user's tenant claim.
        return ExecuteAsync(
            () => maintenanceRequestService.GetByTenantAsync(tenantId, cancellationToken),
            result => Ok(result));
    }

    [HttpGet("property/{propertyId:guid}")]
    [ProducesResponseType<IReadOnlyList<MaintenanceRequestSummaryDto>>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
    public Task<ActionResult<IReadOnlyList<MaintenanceRequestSummaryDto>>> GetByProperty(
        Guid propertyId,
        CancellationToken cancellationToken)
    {
        // TODO: Authorize property access using authenticated landlord claims.
        return ExecuteAsync(
            () => maintenanceRequestService.GetByPropertyAsync(propertyId, cancellationToken),
            result => Ok(result));
    }

    [HttpPut("{id:guid}")]
    [ProducesResponseType<MaintenanceRequestResponseDto>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status409Conflict)]
    public Task<ActionResult<MaintenanceRequestResponseDto>> Update(
        Guid id,
        [FromQuery] Guid tenantId,
        [FromBody] UpdateMaintenanceRequestDto request,
        CancellationToken cancellationToken)
    {
        // TODO: Replace tenantId with the authenticated user's tenant claim.
        return ExecuteAsync(
            () => maintenanceRequestService.UpdateTenantRequestAsync(
                id,
                tenantId,
                request,
                cancellationToken),
            result => Ok(result));
    }

    [HttpPatch("{id:guid}/triage")]
    [ProducesResponseType<MaintenanceRequestResponseDto>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status409Conflict)]
    public Task<ActionResult<MaintenanceRequestResponseDto>> Triage(
        Guid id,
        [FromBody] TriageMaintenanceRequestDto request,
        CancellationToken cancellationToken)
    {
        // TODO: Authorize this operation using authenticated landlord claims.
        return ExecuteAsync(
            () => maintenanceRequestService.TriageAsync(id, request, cancellationToken),
            result => Ok(result));
    }

    [HttpPatch("{id:guid}/assign-technician")]
    [ProducesResponseType<MaintenanceRequestResponseDto>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status409Conflict)]
    public Task<ActionResult<MaintenanceRequestResponseDto>> AssignTechnician(
        Guid id,
        [FromBody] AssignTechnicianDto request,
        CancellationToken cancellationToken)
    {
        // TODO: Authorize this operation using authenticated landlord claims.
        return ExecuteAsync(
            () => maintenanceRequestService.AssignTechnicianAsync(id, request, cancellationToken),
            result => Ok(result));
    }

    private async Task<MaintenanceRequestResponseDto> GetRequiredRequestAsync(
        Guid id,
        CancellationToken cancellationToken)
    {
        return await maintenanceRequestService.GetByIdAsync(id, cancellationToken)
            ?? throw MaintenanceRequestServiceException.NotFound(
                $"Maintenance request '{id}' was not found.");
    }

    private async Task<ActionResult<T>> ExecuteAsync<T>(
        Func<Task<T>> operation,
        Func<T, ActionResult<T>> successResult)
    {
        try
        {
            var result = await operation();
            return successResult(result);
        }
        catch (MaintenanceRequestServiceException exception)
        {
            return MapServiceException(exception);
        }
        catch (OperationCanceledException) when (HttpContext.RequestAborted.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception exception)
        {
            logger.LogError(exception, "An unexpected error occurred while processing a maintenance request.");

            return Problem(
                statusCode: StatusCodes.Status500InternalServerError,
                title: "An unexpected error occurred.",
                detail: "The request could not be completed.");
        }
    }

    private ActionResult MapServiceException(MaintenanceRequestServiceException exception)
    {
        var (statusCode, title) = exception.Error switch
        {
            MaintenanceRequestServiceError.Validation =>
                (StatusCodes.Status400BadRequest, "Invalid maintenance request."),
            MaintenanceRequestServiceError.NotFound =>
                (StatusCodes.Status404NotFound, "Maintenance request not found."),
            MaintenanceRequestServiceError.Conflict =>
                (StatusCodes.Status409Conflict, "Maintenance request conflict."),
            _ =>
                (StatusCodes.Status500InternalServerError, "An unexpected error occurred.")
        };

        return StatusCode(statusCode, new ProblemDetails
        {
            Status = statusCode,
            Title = title,
            Detail = statusCode == StatusCodes.Status500InternalServerError
                ? "The request could not be completed."
                : exception.Message
        });
    }
}
