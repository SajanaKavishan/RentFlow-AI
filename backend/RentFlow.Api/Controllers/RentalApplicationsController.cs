using Microsoft.AspNetCore.Mvc;
using RentFlow.Api.DTOs.RentalApplications;
using RentFlow.Api.Services;
using RentFlow.Api.Services.Interfaces;

namespace RentFlow.Api.Controllers;

/// <summary>
/// Handles HTTP requests for rental applications.
/// </summary>
[ApiController]
[Route("api/rental-applications")]
public class RentalApplicationsController(
    IRentalApplicationService rentalApplicationService,
    ILogger<RentalApplicationsController> logger) : ControllerBase
{
    [HttpPost]
    [ProducesResponseType<RentalApplicationResponseDto>(StatusCodes.Status201Created)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status409Conflict)]
    public Task<ActionResult<RentalApplicationResponseDto>> Create(
        [FromQuery] Guid tenantId,
        [FromBody] CreateRentalApplicationDto request,
        CancellationToken cancellationToken)
    {
        // TODO(auth): Replace tenantId with the authenticated user's ID claim.
        return ExecuteAsync(
            () => rentalApplicationService.CreateAsync(tenantId, request, cancellationToken),
            result => CreatedAtAction(nameof(GetById), new { id = result.Id }, result));
    }

    [HttpGet("{id:guid}")]
    [ProducesResponseType<RentalApplicationResponseDto>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    public Task<ActionResult<RentalApplicationResponseDto>> GetById(
        Guid id,
        CancellationToken cancellationToken)
    {
        return ExecuteAsync(
            () => GetRequiredApplicationAsync(id, cancellationToken),
            result => Ok(result));
    }

    [HttpGet("tenant/{tenantId:guid}")]
    [ProducesResponseType<IReadOnlyList<RentalApplicationResponseDto>>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
    public Task<ActionResult<IReadOnlyList<RentalApplicationResponseDto>>> GetByTenant(
        Guid tenantId,
        CancellationToken cancellationToken)
    {
        // TODO(auth): Authorize tenantId against the authenticated user's ID claim.
        return ExecuteAsync(
            () => rentalApplicationService.GetByTenantAsync(tenantId, cancellationToken),
            result => Ok(result));
    }

    [HttpGet("property/{propertyId:guid}")]
    [ProducesResponseType<IReadOnlyList<RentalApplicationResponseDto>>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
    public Task<ActionResult<IReadOnlyList<RentalApplicationResponseDto>>> GetByProperty(
        Guid propertyId,
        CancellationToken cancellationToken)
    {
        // TODO(auth): Authorize property access using the authenticated landlord.
        return ExecuteAsync(
            () => rentalApplicationService.GetByPropertyAsync(propertyId, cancellationToken),
            result => Ok(result));
    }

    [HttpPut("{id:guid}")]
    [ProducesResponseType<RentalApplicationResponseDto>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status409Conflict)]
    public Task<ActionResult<RentalApplicationResponseDto>> Update(
        Guid id,
        [FromQuery] Guid tenantId,
        [FromBody] UpdateRentalApplicationDto request,
        CancellationToken cancellationToken)
    {
        // TODO(auth): Replace tenantId with the authenticated user's ID claim.
        return ExecuteAsync(
            () => rentalApplicationService.UpdateAsync(id, tenantId, request, cancellationToken),
            result => Ok(result));
    }

    [HttpPatch("{id:guid}/submit")]
    [ProducesResponseType<RentalApplicationResponseDto>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status409Conflict)]
    public Task<ActionResult<RentalApplicationResponseDto>> Submit(
        Guid id,
        [FromQuery] Guid tenantId,
        CancellationToken cancellationToken)
    {
        // TODO(auth): Replace tenantId with the authenticated user's ID claim.
        return ExecuteAsync(
            () => rentalApplicationService.SubmitAsync(id, tenantId, cancellationToken),
            result => Ok(result));
    }

    [HttpPatch("{id:guid}/review")]
    [ProducesResponseType<RentalApplicationResponseDto>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status409Conflict)]
    public Task<ActionResult<RentalApplicationResponseDto>> MarkUnderReview(
        Guid id,
        CancellationToken cancellationToken)
    {
        // TODO(auth): Authorize this operation using the authenticated landlord.
        return ExecuteAsync(
            () => rentalApplicationService.MarkUnderReviewAsync(id, cancellationToken),
            result => Ok(result));
    }

    [HttpPatch("{id:guid}/approve")]
    [ProducesResponseType<RentalApplicationResponseDto>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status409Conflict)]
    public Task<ActionResult<RentalApplicationResponseDto>> Approve(
        Guid id,
        [FromBody] LandlordApplicationDecisionDto request,
        CancellationToken cancellationToken)
    {
        // TODO(auth): Authorize this operation using the authenticated landlord.
        // The route fixes the transition; request.Status cannot select another status.
        return ExecuteAsync(
            () => rentalApplicationService.ApproveAsync(
                id,
                request.LandlordResponse,
                cancellationToken),
            result => Ok(result));
    }

    [HttpPatch("{id:guid}/reject")]
    [ProducesResponseType<RentalApplicationResponseDto>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status409Conflict)]
    public Task<ActionResult<RentalApplicationResponseDto>> Reject(
        Guid id,
        [FromBody] LandlordApplicationDecisionDto request,
        CancellationToken cancellationToken)
    {
        // TODO(auth): Authorize this operation using the authenticated landlord.
        // The route fixes the transition; request.Status cannot select another status.
        return ExecuteAsync(
            () => rentalApplicationService.RejectAsync(
                id,
                request.LandlordResponse ?? string.Empty,
                cancellationToken),
            result => Ok(result));
    }

    [HttpPatch("{id:guid}/request-changes")]
    [ProducesResponseType<RentalApplicationResponseDto>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status409Conflict)]
    public Task<ActionResult<RentalApplicationResponseDto>> RequestChanges(
        Guid id,
        [FromBody] LandlordApplicationDecisionDto request,
        CancellationToken cancellationToken)
    {
        // TODO(auth): Authorize this operation using the authenticated landlord.
        // The route fixes the transition; request.Status cannot select another status.
        return ExecuteAsync(
            () => rentalApplicationService.RequestChangesAsync(
                id,
                request.LandlordResponse ?? string.Empty,
                cancellationToken),
            result => Ok(result));
    }

    [HttpPatch("{id:guid}/withdraw")]
    [ProducesResponseType<RentalApplicationResponseDto>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status409Conflict)]
    public Task<ActionResult<RentalApplicationResponseDto>> Withdraw(
        Guid id,
        [FromQuery] Guid tenantId,
        CancellationToken cancellationToken)
    {
        // TODO(auth): Replace tenantId with the authenticated user's ID claim.
        return ExecuteAsync(
            () => rentalApplicationService.WithdrawAsync(id, tenantId, cancellationToken),
            result => Ok(result));
    }

    private async Task<RentalApplicationResponseDto> GetRequiredApplicationAsync(
        Guid id,
        CancellationToken cancellationToken)
    {
        return await rentalApplicationService.GetByIdAsync(id, cancellationToken)
            ?? throw RentalApplicationServiceException.NotFound(
                $"Rental application '{id}' was not found.");
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
        catch (RentalApplicationServiceException exception)
        {
            return MapServiceException(exception);
        }
        catch (OperationCanceledException) when (HttpContext.RequestAborted.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception exception)
        {
            logger.LogError(
                exception,
                "An unexpected error occurred while processing a rental application request.");

            return Problem(
                statusCode: StatusCodes.Status500InternalServerError,
                title: "An unexpected error occurred.",
                detail: "The request could not be completed.");
        }
    }

    private ActionResult MapServiceException(RentalApplicationServiceException exception)
    {
        var (statusCode, title) = exception.Error switch
        {
            RentalApplicationServiceError.Validation =>
                (StatusCodes.Status400BadRequest, "Invalid rental application request."),
            RentalApplicationServiceError.NotFound =>
                (StatusCodes.Status404NotFound, "Rental application not found."),
            RentalApplicationServiceError.Conflict =>
                (StatusCodes.Status409Conflict, "Rental application conflict."),
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
