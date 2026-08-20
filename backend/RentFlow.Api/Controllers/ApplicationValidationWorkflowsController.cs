using Microsoft.AspNetCore.Mvc;
using RentFlow.Api.DTOs.ApplicationValidation;
using RentFlow.Api.Services;
using RentFlow.Api.Services.Interfaces;

namespace RentFlow.Api.Controllers;

/// <summary>
/// Exposes authoritative validation runs with optional AI-assisted landlord review.
/// </summary>
[ApiController]
[Route("api")]
public class ApplicationValidationWorkflowsController(
    IApplicationValidationOrchestrator orchestrator,
    IApplicationValidationQueryService queryService,
    ILogger<ApplicationValidationWorkflowsController> logger) : ControllerBase
{
    [HttpPost("rental-applications/{applicationId:guid}/validation-runs")]
    [ProducesResponseType<ApplicationValidationWorkflowResponseDto>(StatusCodes.Status201Created)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status409Conflict)]
    public Task<ActionResult<ApplicationValidationWorkflowResponseDto>> StartValidation(
        Guid applicationId,
        CancellationToken cancellationToken)
    {
        // TODO(auth): Authorize the application's property using authenticated landlord claims.
        return ExecuteAsync(
            () => orchestrator.StartValidationAsync(applicationId, cancellationToken),
            workflow => CreatedAtAction(
                nameof(GetById),
                new { workflowId = workflow.Id },
                workflow));
    }

    [HttpGet("rental-applications/{applicationId:guid}/validation-runs")]
    [ProducesResponseType<IReadOnlyList<ApplicationValidationWorkflowResponseDto>>(
        StatusCodes.Status200OK)]
    public Task<ActionResult<IReadOnlyList<ApplicationValidationWorkflowResponseDto>>> GetByApplication(
        Guid applicationId,
        CancellationToken cancellationToken)
    {
        // TODO(auth): Authorize the application's property using authenticated landlord claims.
        return ExecuteAsync(
            () => queryService.GetByApplicationAsync(applicationId, cancellationToken),
            workflows => Ok(workflows));
    }

    [HttpGet("application-validation-workflows/{workflowId:guid}")]
    [ProducesResponseType<ApplicationValidationWorkflowResponseDto>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    public Task<ActionResult<ApplicationValidationWorkflowResponseDto>> GetById(
        Guid workflowId,
        CancellationToken cancellationToken)
    {
        // TODO(auth): Authorize the workflow's property using authenticated landlord claims.
        return ExecuteAsync(
            async () => await queryService.GetByIdAsync(workflowId, cancellationToken)
                ?? throw new ApplicationValidationException(
                    ApplicationValidationError.NotFound,
                    $"Application validation workflow '{workflowId}' was not found."),
            workflow => Ok(workflow));
    }

    private async Task<ActionResult<T>> ExecuteAsync<T>(
        Func<Task<T>> operation,
        Func<T, ActionResult<T>> successResult)
    {
        try
        {
            return successResult(await operation());
        }
        catch (ApplicationValidationException exception)
        {
            return MapValidationException(exception);
        }
        catch (OperationCanceledException) when (HttpContext.RequestAborted.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception exception)
        {
            logger.LogError(
                exception,
                "An unexpected error occurred while processing an application validation request.");

            return Problem(
                statusCode: StatusCodes.Status500InternalServerError,
                title: "An unexpected error occurred.",
                detail: "The validation request could not be completed.");
        }
    }

    private ActionResult MapValidationException(ApplicationValidationException exception)
    {
        var (statusCode, title) = exception.Error switch
        {
            ApplicationValidationError.Validation =>
                (StatusCodes.Status400BadRequest, "Invalid validation request."),
            ApplicationValidationError.NotFound =>
                (StatusCodes.Status404NotFound, "Application validation resource not found."),
            ApplicationValidationError.Conflict =>
                (StatusCodes.Status409Conflict, "Application is not eligible for validation."),
            _ =>
                (StatusCodes.Status500InternalServerError, "An unexpected error occurred.")
        };

        return StatusCode(statusCode, new ProblemDetails
        {
            Status = statusCode,
            Title = title,
            Detail = statusCode == StatusCodes.Status500InternalServerError
                ? "The validation request could not be completed."
                : exception.Message
        });
    }
}
