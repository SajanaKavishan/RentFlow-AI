using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using RentFlow.Api.DTOs.RentalOffers;
using RentFlow.Api.Models;
using RentFlow.Api.Services;
using RentFlow.Api.Services.Interfaces;

namespace RentFlow.Api.Controllers;

/// <summary>
/// Handles HTTP requests for rental offers.
/// </summary>
[ApiController]
[Route("api/rental-offers")]
[Authorize]
public class RentalOffersController(
    IRentalOfferService rentalOfferService,
    ICurrentUserService currentUser,
    ILogger<RentalOffersController> logger) : ControllerBase
{
    [HttpPost]
    [Authorize(Roles = $"{nameof(UserRole.Landlord)},{nameof(UserRole.Admin)}")]
    [ProducesResponseType<RentalOfferResponseDto>(StatusCodes.Status201Created)]
    [ProducesResponseType<ValidationProblemDetails>(StatusCodes.Status400BadRequest)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status409Conflict)]
    public Task<ActionResult<RentalOfferResponseDto>> Create(
        [FromBody] CreateRentalOfferDto dto,
        CancellationToken cancellationToken)
    {
        return ExecuteAsync(
            async () => await rentalOfferService.CreateAsync(
                dto,
                cancellationToken),
            result => CreatedAtAction(
                nameof(GetById),
                new { id = result.Id },
                result));
    }

    [HttpGet("mine")]
    [Authorize(Roles = nameof(UserRole.Tenant))]
    [ProducesResponseType<IReadOnlyList<RentalOfferResponseDto>>(StatusCodes.Status200OK)]
    public Task<ActionResult<IReadOnlyList<RentalOfferResponseDto>>> GetMine(
        CancellationToken cancellationToken)
    {
        var tenantId = GetRequiredUserId();

        return ExecuteAsync(
            async () => await rentalOfferService.GetByTenantAsync(
                tenantId,
                cancellationToken),
            result => Ok(result));
    }

    [HttpPatch("{id:guid}/accept")]
    [Authorize(Roles = nameof(UserRole.Tenant))]
    [ProducesResponseType<RentalOfferResponseDto>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status409Conflict)]
    public Task<ActionResult<RentalOfferResponseDto>> Accept(
        Guid id,
        CancellationToken cancellationToken)
    {
        var tenantId = GetRequiredUserId();

        return ExecuteAsync(
            async () => await rentalOfferService.AcceptAsync(
                id,
                tenantId,
                cancellationToken),
            result => Ok(result));
    }

    [HttpPatch("{id:guid}/reject")]
    [Authorize(Roles = nameof(UserRole.Tenant))]
    [ProducesResponseType<RentalOfferResponseDto>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status409Conflict)]
    public Task<ActionResult<RentalOfferResponseDto>> Reject(
        Guid id,
        CancellationToken cancellationToken)
    {
        var tenantId = GetRequiredUserId();

        return ExecuteAsync(
            async () => await rentalOfferService.RejectAsync(
                id,
                tenantId,
                cancellationToken),
            result => Ok(result));
    }

    [HttpPatch("{id:guid}/withdraw")]
    [Authorize(Roles = $"{nameof(UserRole.Landlord)},{nameof(UserRole.Admin)}")]
    [ProducesResponseType<RentalOfferResponseDto>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status409Conflict)]
    public Task<ActionResult<RentalOfferResponseDto>> Withdraw(
        Guid id,
        CancellationToken cancellationToken)
    {
        return ExecuteAsync(
            async () => await rentalOfferService.WithdrawAsync(
                id,
                cancellationToken),
            result => Ok(result));
    }

    [HttpGet("{id:guid}")]
    [Authorize(Roles = $"{nameof(UserRole.Tenant)},{nameof(UserRole.Landlord)},{nameof(UserRole.Admin)}")]
    [ProducesResponseType<RentalOfferResponseDto>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    public Task<ActionResult<RentalOfferResponseDto>> GetById(
        Guid id,
        CancellationToken cancellationToken)
    {
        return ExecuteAsync(
            async () =>
            {
                var offer = await rentalOfferService.GetByIdAsync(
                    id,
                    cancellationToken);

                return offer
                    ?? throw RentalOfferServiceException.NotFound(
                        $"Rental offer '{id}' was not found.");
            },
            result => Ok(result));
    }

    private Guid GetRequiredUserId() => currentUser.UserId
        ?? throw new InvalidOperationException(
            "The authenticated JWT has no valid user ID.");

    private async Task<ActionResult<T>> ExecuteAsync<T>(
        Func<Task<T>> operation,
        Func<T, ActionResult<T>> successResult)
    {
        try
        {
            var result = await operation();
            return successResult(result);
        }
        catch (RentalOfferServiceException exception)
        {
            return MapServiceException(exception);
        }
        catch (OperationCanceledException)
            when (HttpContext.RequestAborted.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception exception)
        {
            logger.LogError(
                exception,
                "An unexpected error occurred while processing a rental offer request.");

            return Problem(
                statusCode: StatusCodes.Status500InternalServerError,
                title: "An unexpected error occurred.",
                detail: "The request could not be completed.");
        }
    }

    private ActionResult MapServiceException(
        RentalOfferServiceException exception)
    {
        var (statusCode, title) = exception.Error switch
        {
            RentalOfferServiceError.Validation =>
                (StatusCodes.Status400BadRequest, "Invalid rental offer request."),

            RentalOfferServiceError.NotFound =>
                (StatusCodes.Status404NotFound, "Rental offer not found."),

            RentalOfferServiceError.Conflict =>
                (StatusCodes.Status409Conflict, "Rental offer conflict."),

            _ =>
                (StatusCodes.Status500InternalServerError,
                    "An unexpected error occurred.")
        };

        return Problem(
            statusCode: statusCode,
            title: title,
            detail: exception.Message);
    }
}