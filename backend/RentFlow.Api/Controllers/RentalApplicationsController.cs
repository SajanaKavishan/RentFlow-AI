using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using RentFlow.Api.DTOs.RentalApplications;
using RentFlow.Api.Models;
using RentFlow.Api.Services;
using RentFlow.Api.Services.Interfaces;

namespace RentFlow.Api.Controllers;

/// <summary>
/// Handles HTTP requests for rental applications.
/// </summary>
[ApiController]
[Route("api/rental-applications")]
[Authorize]
public class RentalApplicationsController(
    IRentalApplicationService rentalApplicationService,
    IPropertyAccessGuard propertyAccessGuard,
    ICurrentUserService currentUser,
    ILogger<RentalApplicationsController> logger) : ControllerBase
{
    [HttpPost]
    [Authorize(Roles = nameof(UserRole.Tenant))]
    [ProducesResponseType<RentalApplicationResponseDto>(StatusCodes.Status201Created)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status409Conflict)]
    public Task<ActionResult<RentalApplicationResponseDto>> Create(
        [FromBody] CreateRentalApplicationDto request,
        CancellationToken cancellationToken)
    {
        return ExecuteAsync(
            () => rentalApplicationService.CreateAsync(GetRequiredUserId(), request, cancellationToken),
            result => CreatedAtAction(nameof(GetById), new { id = result.Id }, result));
    }

    [HttpGet("{id:guid}")]
    [Authorize(Roles = $"{nameof(UserRole.Tenant)},{nameof(UserRole.Landlord)},{nameof(UserRole.Admin)}")]
    [ProducesResponseType<RentalApplicationResponseDto>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    public Task<ActionResult<RentalApplicationResponseDto>> GetById(
        Guid id,
        CancellationToken cancellationToken)
    {
        return ExecuteAsync(
            () => GetAuthorizedApplicationAsync(id, cancellationToken),
            result => Ok(result));
    }

    [HttpGet]
    [Authorize(Roles = nameof(UserRole.Tenant))]
    [ProducesResponseType<IReadOnlyList<RentalApplicationResponseDto>>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
    public Task<ActionResult<IReadOnlyList<RentalApplicationResponseDto>>> GetMine(
        CancellationToken cancellationToken)
    {
        return ExecuteAsync(
            () => rentalApplicationService.GetByTenantAsync(GetRequiredUserId(), cancellationToken),
            result => Ok(result));
    }

    [HttpGet("property/{propertyId:guid}")]
    [Authorize(Roles = $"{nameof(UserRole.Landlord)},{nameof(UserRole.Admin)}")]
    [ProducesResponseType<IReadOnlyList<RentalApplicationResponseDto>>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
    public Task<ActionResult<IReadOnlyList<RentalApplicationResponseDto>>> GetByProperty(
        Guid propertyId,
        CancellationToken cancellationToken)
    {
        return ExecuteAsync(
            async () =>
            {
                await EnsureLandlordCanAccessPropertyAsync(propertyId, cancellationToken);
                return await rentalApplicationService.GetByPropertyAsync(
                    propertyId, cancellationToken);
            },
            result => Ok(result));
    }

    [HttpPut("{id:guid}")]
    [Authorize(Roles = nameof(UserRole.Tenant))]
    [ProducesResponseType<RentalApplicationResponseDto>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status409Conflict)]
    public Task<ActionResult<RentalApplicationResponseDto>> Update(
        Guid id,
        [FromBody] UpdateRentalApplicationDto request,
        CancellationToken cancellationToken)
    {
        return ExecuteAsync(
            () => rentalApplicationService.UpdateAsync(id, GetRequiredUserId(), request, cancellationToken),
            result => Ok(result));
    }

    [HttpPatch("{id:guid}/submit")]
    [Authorize(Roles = nameof(UserRole.Tenant))]
    [ProducesResponseType<RentalApplicationResponseDto>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status409Conflict)]
    public Task<ActionResult<RentalApplicationResponseDto>> Submit(
        Guid id,
        CancellationToken cancellationToken)
    {
        return ExecuteAsync(
            () => rentalApplicationService.SubmitAsync(id, GetRequiredUserId(), cancellationToken),
            result => Ok(result));
    }

    [HttpPatch("{id:guid}/review")]
    [Authorize(Roles = $"{nameof(UserRole.Landlord)},{nameof(UserRole.Admin)}")]
    [ProducesResponseType<RentalApplicationResponseDto>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status409Conflict)]
    public Task<ActionResult<RentalApplicationResponseDto>> MarkUnderReview(
        Guid id,
        CancellationToken cancellationToken)
    {
        return ExecuteAsync(
            async () =>
            {
                await EnsureLandlordCanAccessApplicationAsync(id, cancellationToken);
                return await rentalApplicationService.MarkUnderReviewAsync(
                    id, cancellationToken);
            },
            result => Ok(result));
    }

    [HttpPatch("{id:guid}/approve")]
    [Authorize(Roles = $"{nameof(UserRole.Landlord)},{nameof(UserRole.Admin)}")]
    [ProducesResponseType<RentalApplicationResponseDto>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status409Conflict)]
    public Task<ActionResult<RentalApplicationResponseDto>> Approve(
        Guid id,
        [FromBody] LandlordApplicationDecisionDto request,
        CancellationToken cancellationToken)
    {
        // The route fixes the transition; request.Status cannot select another status.
        return ExecuteAsync(
            async () =>
            {
                await EnsureLandlordCanAccessApplicationAsync(id, cancellationToken);
                return await rentalApplicationService.ApproveAsync(
                    id,
                    request.LandlordResponse,
                    cancellationToken);
            },
            result => Ok(result));
    }

    [HttpPatch("{id:guid}/reject")]
    [Authorize(Roles = $"{nameof(UserRole.Landlord)},{nameof(UserRole.Admin)}")]
    [ProducesResponseType<RentalApplicationResponseDto>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status409Conflict)]
    public Task<ActionResult<RentalApplicationResponseDto>> Reject(
        Guid id,
        [FromBody] LandlordApplicationDecisionDto request,
        CancellationToken cancellationToken)
    {
        // The route fixes the transition; request.Status cannot select another status.
        return ExecuteAsync(
            async () =>
            {
                await EnsureLandlordCanAccessApplicationAsync(id, cancellationToken);
                return await rentalApplicationService.RejectAsync(
                    id,
                    request.LandlordResponse ?? string.Empty,
                    cancellationToken);
            },
            result => Ok(result));
    }

    [HttpPatch("{id:guid}/request-changes")]
    [Authorize(Roles = $"{nameof(UserRole.Landlord)},{nameof(UserRole.Admin)}")]
    [ProducesResponseType<RentalApplicationResponseDto>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status409Conflict)]
    public Task<ActionResult<RentalApplicationResponseDto>> RequestChanges(
        Guid id,
        [FromBody] LandlordApplicationDecisionDto request,
        CancellationToken cancellationToken)
    {
        // The route fixes the transition; request.Status cannot select another status.
        return ExecuteAsync(
            async () =>
            {
                await EnsureLandlordCanAccessApplicationAsync(id, cancellationToken);
                return await rentalApplicationService.RequestChangesAsync(
                    id,
                    request.LandlordResponse ?? string.Empty,
                    cancellationToken);
            },
            result => Ok(result));
    }

    [HttpPatch("{id:guid}/withdraw")]
    [Authorize(Roles = nameof(UserRole.Tenant))]
    [ProducesResponseType<RentalApplicationResponseDto>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status409Conflict)]
    public Task<ActionResult<RentalApplicationResponseDto>> Withdraw(
        Guid id,
        CancellationToken cancellationToken)
    {
        return ExecuteAsync(
            () => rentalApplicationService.WithdrawAsync(id, GetRequiredUserId(), cancellationToken),
            result => Ok(result));
    }

    private async Task<RentalApplicationResponseDto> GetAuthorizedApplicationAsync(
        Guid id,
        CancellationToken cancellationToken)
    {
        if (currentUser.Role == UserRole.Tenant)
        {
            return await rentalApplicationService.GetByIdForTenantAsync(
                    id,
                    GetRequiredUserId(),
                    cancellationToken)
                ?? throw RentalApplicationServiceException.NotFound(
                    $"Rental application '{id}' was not found.");
        }

        await EnsureLandlordCanAccessApplicationAsync(id, cancellationToken);
        var application = await rentalApplicationService.GetByIdAsync(id, cancellationToken);

        return application
            ?? throw RentalApplicationServiceException.NotFound(
                $"Rental application '{id}' was not found.");
    }

    private async Task EnsureLandlordCanAccessPropertyAsync(
        Guid propertyId,
        CancellationToken cancellationToken)
    {
        if (currentUser.Role == UserRole.Landlord
            && !await propertyAccessGuard.CanAccessPropertyAsync(
                GetRequiredUserId(), propertyId, cancellationToken))
        {
            throw RentalApplicationServiceException.NotFound(
                $"Property '{propertyId}' was not found.");
        }
    }

    private async Task EnsureLandlordCanAccessApplicationAsync(
        Guid applicationId,
        CancellationToken cancellationToken)
    {
        if (currentUser.Role == UserRole.Landlord
            && !await propertyAccessGuard.CanAccessApplicationAsync(
                GetRequiredUserId(), applicationId, cancellationToken))
        {
            throw RentalApplicationServiceException.NotFound(
                $"Rental application '{applicationId}' was not found.");
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
