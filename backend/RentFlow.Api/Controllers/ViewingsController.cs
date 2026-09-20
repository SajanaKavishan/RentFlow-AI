using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using RentFlow.Api.DTOs.Viewings;
using RentFlow.Api.Models;
using RentFlow.Api.Services;
using RentFlow.Api.Services.Interfaces;

namespace RentFlow.Api.Controllers;

/// <summary>
/// Handles HTTP requests for the Viewing Booking feature.
/// </summary>
[ApiController]
[Route("api/viewings")]
[Authorize]
public class ViewingsController(
    IViewingService viewingService,
    IPropertyAccessGuard propertyAccessGuard,
    ICurrentUserService currentUser,
    ILogger<ViewingsController> logger) : ControllerBase
{
    [HttpPost]
    [Authorize(Roles = nameof(UserRole.Tenant))]
    [ProducesResponseType<ViewingResponseDto>(StatusCodes.Status201Created)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status409Conflict)]
    public Task<ActionResult<ViewingResponseDto>> Create(
        [FromBody] CreateViewingRequestDto request,
        CancellationToken cancellationToken)
    {
        return ExecuteAsync(
            () => viewingService.CreateAsync(GetRequiredUserId(), request, cancellationToken),
            result => CreatedAtAction(nameof(GetById), new { id = result.Id }, result));
    }

    [HttpGet("{id:guid}")]
    [Authorize(Roles = $"{nameof(UserRole.Tenant)},{nameof(UserRole.Landlord)},{nameof(UserRole.Admin)}")]
    [ProducesResponseType<ViewingResponseDto>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    public Task<ActionResult<ViewingResponseDto>> GetById(
        Guid id,
        CancellationToken cancellationToken)
    {
        return ExecuteAsync(
            () => GetAuthorizedViewingAsync(id, cancellationToken),
            result => Ok(result));
    }

    [HttpGet]
    [Authorize(Roles = nameof(UserRole.Tenant))]
    [ProducesResponseType<IReadOnlyList<ViewingResponseDto>>(StatusCodes.Status200OK)]
    public Task<ActionResult<IReadOnlyList<ViewingResponseDto>>> GetMine(
        CancellationToken cancellationToken)
    {
        return ExecuteAsync(
            () => viewingService.GetByTenantAsync(GetRequiredUserId(), cancellationToken),
            result => Ok(result));
    }

    [HttpGet("property/{propertyId:guid}")]
    [Authorize(Roles = $"{nameof(UserRole.Landlord)},{nameof(UserRole.Admin)}")]
    [ProducesResponseType<IReadOnlyList<ViewingResponseDto>>(StatusCodes.Status200OK)]
    public Task<ActionResult<IReadOnlyList<ViewingResponseDto>>> GetByProperty(
        Guid propertyId,
        CancellationToken cancellationToken)
    {
        return ExecuteAsync(
            async () =>
            {
                await EnsureLandlordCanAccessPropertyAsync(propertyId, cancellationToken);
                return await viewingService.GetByPropertyAsync(propertyId, cancellationToken);
            },
            result => Ok(result));
    }

    [HttpPatch("{id:guid}/approve")]
    [Authorize(Roles = $"{nameof(UserRole.Landlord)},{nameof(UserRole.Admin)}")]
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
            async () =>
            {
                await EnsureLandlordCanAccessViewingAsync(id, cancellationToken);
                return await viewingService.ApproveAsync(
                    id, request.LandlordResponse, cancellationToken);
            },
            result => Ok(result));
    }

    [HttpPatch("{id:guid}/reject")]
    [Authorize(Roles = $"{nameof(UserRole.Landlord)},{nameof(UserRole.Admin)}")]
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
            async () =>
            {
                await EnsureLandlordCanAccessViewingAsync(id, cancellationToken);
                return await viewingService.RejectAsync(
                    id, request.LandlordResponse ?? string.Empty, cancellationToken);
            },
            result => Ok(result));
    }

    [HttpPatch("{id:guid}/cancel")]
    [Authorize(Roles = nameof(UserRole.Tenant))]
    [ProducesResponseType<ViewingResponseDto>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status409Conflict)]
    public Task<ActionResult<ViewingResponseDto>> Cancel(
        Guid id,
        CancellationToken cancellationToken)
    {
        return ExecuteAsync(
            () => viewingService.CancelAsync(id, GetRequiredUserId(), cancellationToken),
            result => Ok(result));
    }

    private async Task<ViewingResponseDto> GetAuthorizedViewingAsync(
        Guid id,
        CancellationToken cancellationToken)
    {
        if (currentUser.Role == UserRole.Tenant)
        {
            return await viewingService.GetByIdForTenantAsync(
                    id, GetRequiredUserId(), cancellationToken)
                ?? throw ViewingServiceException.NotFound(
                    $"Viewing request '{id}' was not found.");
        }

        await EnsureLandlordCanAccessViewingAsync(id, cancellationToken);
        var viewing = await viewingService.GetByIdAsync(id, cancellationToken);

        return viewing
            ?? throw ViewingServiceException.NotFound($"Viewing request '{id}' was not found.");
    }

    private async Task EnsureLandlordCanAccessPropertyAsync(
        Guid propertyId,
        CancellationToken cancellationToken)
    {
        if (currentUser.Role == UserRole.Landlord
            && !await propertyAccessGuard.CanAccessPropertyAsync(
                GetRequiredUserId(), propertyId, cancellationToken))
        {
            throw ViewingServiceException.NotFound(
                $"Property '{propertyId}' was not found.");
        }
    }

    private async Task EnsureLandlordCanAccessViewingAsync(
        Guid viewingId,
        CancellationToken cancellationToken)
    {
        if (currentUser.Role == UserRole.Landlord
            && !await propertyAccessGuard.CanAccessViewingAsync(
                GetRequiredUserId(), viewingId, cancellationToken))
        {
            throw ViewingServiceException.NotFound(
                $"Viewing request '{viewingId}' was not found.");
        }
    }

    private Guid GetRequiredUserId() => currentUser.UserId
        ?? throw new InvalidOperationException("The authenticated JWT has no valid user ID.");

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
