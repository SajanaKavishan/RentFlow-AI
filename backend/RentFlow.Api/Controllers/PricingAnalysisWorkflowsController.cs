using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using RentFlow.Api.DTOs.PricingAnalysis;
using RentFlow.Api.Models;
using RentFlow.Api.Services;
using RentFlow.Api.Services.Interfaces;

namespace RentFlow.Api.Controllers;

/// <summary>
/// Exposes advisory rental price analysis workflows to landlords and administrators.
/// </summary>
[ApiController]
[Route("api")]
[Authorize(Roles = $"{nameof(UserRole.Landlord)},{nameof(UserRole.Admin)}")]
public sealed class PricingAnalysisWorkflowsController(
    IPricingAnalysisOrchestrator orchestrator,
    IPricingAnalysisQueryService queryService,
    IPropertyAccessGuard propertyAccessGuard,
    ICurrentUserService currentUser,
    ILogger<PricingAnalysisWorkflowsController> logger) : ControllerBase
{
    [HttpPost("properties/{propertyId:guid}/pricing-analysis-workflows")]
    [ProducesResponseType<PricingAnalysisWorkflowResponseDto>(StatusCodes.Status201Created)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    public Task<ActionResult<PricingAnalysisWorkflowResponseDto>> Start(
        Guid propertyId,
        CancellationToken cancellationToken)
    {
        return ExecuteAsync(
            async () =>
            {
                await EnsureLandlordCanAccessPropertyAsync(propertyId, cancellationToken);
                return await orchestrator.StartAsync(propertyId, cancellationToken);
            },
            workflow => CreatedAtAction(
                nameof(GetById),
                new { workflowId = workflow.WorkflowId },
                workflow));
    }

    [HttpGet("properties/{propertyId:guid}/pricing-analysis-workflows")]
    [ProducesResponseType<IReadOnlyList<PricingAnalysisWorkflowResponseDto>>(
        StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    public Task<ActionResult<IReadOnlyList<PricingAnalysisWorkflowResponseDto>>> GetByProperty(
        Guid propertyId,
        CancellationToken cancellationToken)
    {
        return ExecuteAsync(
            async () =>
            {
                await EnsureLandlordCanAccessPropertyAsync(propertyId, cancellationToken);
                return await queryService.GetByPropertyAsync(propertyId, cancellationToken);
            },
            workflows => Ok(workflows));
    }

    [HttpGet("pricing-analysis-workflows/{workflowId:guid}")]
    [ProducesResponseType<PricingAnalysisWorkflowResponseDto>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    public Task<ActionResult<PricingAnalysisWorkflowResponseDto>> GetById(
        Guid workflowId,
        CancellationToken cancellationToken)
    {
        return ExecuteAsync(
            async () =>
            {
                await EnsureLandlordCanAccessWorkflowAsync(workflowId, cancellationToken);
                return await queryService.GetByIdAsync(workflowId, cancellationToken)
                    ?? throw new PricingAnalysisException(
                        PricingAnalysisError.NotFound,
                        "The pricing analysis workflow was not found.");
            },
            workflow => Ok(workflow));
    }

    private async Task EnsureLandlordCanAccessPropertyAsync(
        Guid propertyId,
        CancellationToken cancellationToken)
    {
        if (currentUser.Role == UserRole.Landlord
            && !await propertyAccessGuard.CanAccessPropertyAsync(
                GetRequiredUserId(), propertyId, cancellationToken))
        {
            throw new PricingAnalysisException(
                PricingAnalysisError.NotFound,
                "The property was not found.");
        }
    }

    private async Task EnsureLandlordCanAccessWorkflowAsync(
        Guid workflowId,
        CancellationToken cancellationToken)
    {
        if (currentUser.Role == UserRole.Landlord
            && !await propertyAccessGuard.CanAccessPricingAnalysisWorkflowAsync(
                GetRequiredUserId(), workflowId, cancellationToken))
        {
            throw new PricingAnalysisException(
                PricingAnalysisError.NotFound,
                "The pricing analysis workflow was not found.");
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
            return successResult(await operation());
        }
        catch (PricingAnalysisException exception)
        {
            return MapPricingException(exception);
        }
        catch (OperationCanceledException) when (HttpContext.RequestAborted.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception exception)
        {
            logger.LogError(exception, "An unexpected error occurred while processing a pricing analysis request.");
            return Problem(
                statusCode: StatusCodes.Status500InternalServerError,
                title: "An unexpected error occurred.",
                detail: "The pricing analysis request could not be completed.");
        }
    }

    private ActionResult MapPricingException(PricingAnalysisException exception)
    {
        var (statusCode, title) = exception.Error switch
        {
            PricingAnalysisError.Validation =>
                (StatusCodes.Status400BadRequest, "Invalid pricing analysis request."),
            PricingAnalysisError.NotFound =>
                (StatusCodes.Status404NotFound, "Pricing analysis resource not found."),
            _ =>
                (StatusCodes.Status500InternalServerError, "An unexpected error occurred.")
        };

        return StatusCode(statusCode, new ProblemDetails
        {
            Status = statusCode,
            Title = title,
            Detail = statusCode == StatusCodes.Status500InternalServerError
                ? "The pricing analysis request could not be completed."
                : exception.Message
        });
    }
}
