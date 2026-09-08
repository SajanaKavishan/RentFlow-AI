using Microsoft.AspNetCore.Mvc;
using RentFlow.Api.DTOs.ApplicationDocuments;
using RentFlow.Api.Services;
using RentFlow.Api.Services.Interfaces;

namespace RentFlow.Api.Controllers;

/// <summary>
/// Handles HTTP requests for rental application documents.
/// </summary>
[ApiController]
[Route("api")]
public class ApplicationDocumentsController(
    IApplicationDocumentService applicationDocumentService,
    ILogger<ApplicationDocumentsController> logger) : ControllerBase
{
    [HttpPost("rental-applications/{applicationId:guid}/documents")]
    [Consumes("multipart/form-data")]
    [ProducesResponseType<ApplicationDocumentResponseDto>(StatusCodes.Status201Created)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status409Conflict)]
    public async Task<ActionResult<ApplicationDocumentResponseDto>> Upload(
        Guid applicationId,
        [FromQuery] Guid tenantId,
        [FromForm] UploadApplicationDocumentDto request,
        CancellationToken cancellationToken)
    {
        // TODO(auth): Replace tenantId with the authenticated user's ID claim.
        await using var content = request.File.OpenReadStream();

        return await ExecuteAsync(
            () => applicationDocumentService.UploadAsync(
                applicationId,
                tenantId,
                request.DocumentType!.Value,
                content,
                request.File.FileName,
                request.File.ContentType,
                request.File.Length,
                cancellationToken),
            result => CreatedAtAction(
                nameof(GetById),
                new { documentId = result.Id, tenantId },
                result));
    }

    [HttpGet("rental-applications/{applicationId:guid}/documents")]
    [ProducesResponseType<IReadOnlyList<ApplicationDocumentResponseDto>>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    public Task<ActionResult<IReadOnlyList<ApplicationDocumentResponseDto>>> GetByApplication(
        Guid applicationId,
        [FromQuery] Guid tenantId,
        CancellationToken cancellationToken)
    {
        // TODO(auth): Replace tenantId with the authenticated user's ID or authorized landlord identity.
        return ExecuteAsync(
            () => applicationDocumentService.GetByApplicationAsync(
                applicationId,
                tenantId,
                cancellationToken),
            result => Ok(result));
    }

    [HttpGet("application-documents/{documentId:guid}")]
    [ProducesResponseType<ApplicationDocumentResponseDto>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    public Task<ActionResult<ApplicationDocumentResponseDto>> GetById(
        Guid documentId,
        [FromQuery] Guid tenantId,
        CancellationToken cancellationToken)
    {
        // TODO(auth): Replace tenantId with the authenticated user's ID or authorized landlord identity.
        return ExecuteAsync(
            async () => await applicationDocumentService.GetByIdAsync(
                documentId,
                tenantId,
                cancellationToken)
                ?? throw ApplicationDocumentServiceException.NotFound(
                    "The application document was not found."),
            result => Ok(result));
    }

    [HttpGet("application-documents/{documentId:guid}/download")]
    [ProducesResponseType(StatusCodes.Status302Found)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    public Task<IActionResult> Download(
        Guid documentId,
        [FromQuery] Guid tenantId,
        CancellationToken cancellationToken)
    {
        // TODO(auth): Replace tenantId with the authenticated user's ID or authorized landlord identity.
        return ExecuteAsync(async () =>
        {
            var signedUrl = await applicationDocumentService.GenerateDownloadUrlAsync(
                documentId,
                tenantId,
                cancellationToken);
            return Redirect(signedUrl);
        });
    }

    [HttpDelete("application-documents/{documentId:guid}")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status409Conflict)]
    public Task<IActionResult> Delete(
        Guid documentId,
        [FromQuery] Guid tenantId,
        CancellationToken cancellationToken)
    {
        // TODO(auth): Replace tenantId with the authenticated user's ID claim.
        return ExecuteAsync(async () =>
        {
            await applicationDocumentService.DeleteAsync(
                documentId,
                tenantId,
                cancellationToken);
            return NoContent();
        });
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
        catch (ApplicationDocumentServiceException exception)
        {
            return MapServiceException(exception);
        }
        catch (OperationCanceledException) when (HttpContext.RequestAborted.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception exception)
        {
            return HandleUnexpectedException(exception);
        }
    }

    private async Task<IActionResult> ExecuteAsync(Func<Task<IActionResult>> operation)
    {
        try
        {
            return await operation();
        }
        catch (ApplicationDocumentServiceException exception)
        {
            return MapServiceException(exception);
        }
        catch (OperationCanceledException) when (HttpContext.RequestAborted.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception exception)
        {
            return HandleUnexpectedException(exception);
        }
    }

    private ObjectResult MapServiceException(ApplicationDocumentServiceException exception)
    {
        var (statusCode, title) = exception.Error switch
        {
            ApplicationDocumentServiceError.Validation =>
                (StatusCodes.Status400BadRequest, "Invalid application document request."),
            ApplicationDocumentServiceError.NotFound =>
                (StatusCodes.Status404NotFound, "Application document not found."),
            ApplicationDocumentServiceError.Conflict =>
                (StatusCodes.Status409Conflict, "Application document conflict."),
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

    private ObjectResult HandleUnexpectedException(Exception exception)
    {
        logger.LogError(
            exception,
            "An unexpected error occurred while processing an application document request.");

        return Problem(
            statusCode: StatusCodes.Status500InternalServerError,
            title: "An unexpected error occurred.",
            detail: "The request could not be completed.");
    }
}
