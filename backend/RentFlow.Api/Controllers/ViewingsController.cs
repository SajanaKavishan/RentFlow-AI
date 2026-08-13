using Microsoft.AspNetCore.Mvc;
using RentFlow.Api.DTOs.Viewings;
using RentFlow.Api.Services;
using RentFlow.Api.Services.Interfaces;

namespace RentFlow.Api.Controllers;

/// <summary>
/// Handles HTTP requests for the Viewing Booking feature.
/// </summary>
[ApiController]
[Route("api/viewings")]
public class ViewingsController(
    IViewingService viewingService,
    ILogger<ViewingsController> logger) : ControllerBase
{
    [HttpPost]
    [ProducesResponseType<ViewingResponseDto>(StatusCodes.Status201Created)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status409Conflict)]
    public Task<ActionResult<ViewingResponseDto>> Create(
        [FromQuery] Guid tenantId,
        [FromBody] CreateViewingRequestDto request,
        CancellationToken cancellationToken)
    {
        // TODO: Replace tenantId with the authenticated user's tenant claim.
        return ExecuteAsync(
            () => viewingService.CreateAsync(tenantId, request, cancellationToken),
            result => CreatedAtAction(nameof(GetById), new { id = result.Id }, result));
    }

    [HttpGet("{id:guid}")]
    [ProducesResponseType<ViewingResponseDto>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    public Task<ActionResult<ViewingResponseDto>> GetById(
        Guid id,
        CancellationToken cancellationToken)
    {
        return ExecuteAsync(
            () => GetRequiredViewingAsync(id, cancellationToken),
            result => Ok(result));
    }

    [HttpGet("tenant/{tenantId:guid}")]
    [ProducesResponseType<IReadOnlyList<ViewingResponseDto>>(StatusCodes.Status200OK)]
    public Task<ActionResult<IReadOnlyList<ViewingResponseDto>>> GetByTenant(
        Guid tenantId,
        CancellationToken cancellationToken)
    {
        return ExecuteAsync(
            () => viewingService.GetByTenantAsync(tenantId, cancellationToken),
            result => Ok(result));
    }

    [HttpGet("property/{propertyId:guid}")]
    [ProducesResponseType<IReadOnlyList<ViewingResponseDto>>(StatusCodes.Status200OK)]
    public Task<ActionResult<IReadOnlyList<ViewingResponseDto>>> GetByProperty(
        Guid propertyId,
        CancellationToken cancellationToken)
    {
        return ExecuteAsync(
            () => viewingService.GetByPropertyAsync(propertyId, cancellationToken),
            result => Ok(result));
    }

    [HttpPatch("{id:guid}/approve")]
    [ProducesResponseType<ViewingResponseDto>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status409Conflict)]
    public Task<ActionResult<ViewingResponseDto>> Approve(
        Guid id,
        [FromBody] UpdateViewingStatusDto request,
        CancellationToken cancellationToken)
    {
        // The route fixes the transition; request.Status cannot select another status.
        return ExecuteAsync(
            () => viewingService.ApproveAsync(id, request.LandlordResponse, cancellationToken),
            result => Ok(result));
    }

    [HttpPatch("{id:guid}/reject")]
    [ProducesResponseType<ViewingResponseDto>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status409Conflict)]
    public Task<ActionResult<ViewingResponseDto>> Reject(
        Guid id,
        [FromBody] UpdateViewingStatusDto request,
        CancellationToken cancellationToken)
    {
        // The route fixes the transition; request.Status cannot select another status.
        return ExecuteAsync(
            () => viewingService.RejectAsync(id, request.LandlordResponse ?? string.Empty, cancellationToken),
            result => Ok(result));
    }

    [HttpPatch("{id:guid}/cancel")]
    [ProducesResponseType<ViewingResponseDto>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status409Conflict)]
    public Task<ActionResult<ViewingResponseDto>> Cancel(
        Guid id,
        [FromQuery] Guid tenantId,
        CancellationToken cancellationToken)
    {
        // TODO: Replace tenantId with the authenticated user's tenant claim.
        return ExecuteAsync(
            () => viewingService.CancelAsync(id, tenantId, cancellationToken),
            result => Ok(result));
    }

    private async Task<ViewingResponseDto> GetRequiredViewingAsync(
        Guid id,
        CancellationToken cancellationToken)
    {
        return await viewingService.GetByIdAsync(id, cancellationToken)
            ?? throw ViewingServiceException.NotFound($"Viewing request '{id}' was not found.");
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
        catch (ViewingServiceException exception)
        {
            return MapServiceException(exception);
        }
        catch (OperationCanceledException) when (HttpContext.RequestAborted.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception exception)
        {
            logger.LogError(exception, "An unexpected error occurred while processing a viewing request.");

            return Problem(
                statusCode: StatusCodes.Status500InternalServerError,
                title: "An unexpected error occurred.",
                detail: "The request could not be completed.");
        }
    }

    private ActionResult MapServiceException(ViewingServiceException exception)
    {
        var (statusCode, title) = exception.Error switch
        {
            ViewingServiceError.Validation =>
                (StatusCodes.Status400BadRequest, "Invalid viewing request."),
            ViewingServiceError.NotFound =>
                (StatusCodes.Status404NotFound, "Viewing request not found."),
            ViewingServiceError.Conflict =>
                (StatusCodes.Status409Conflict, "Viewing request conflict."),
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
