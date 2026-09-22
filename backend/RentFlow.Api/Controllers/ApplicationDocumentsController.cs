using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using RentFlow.Api.DTOs.ApplicationDocuments;
using RentFlow.Api.Models;
using RentFlow.Api.Services;
using RentFlow.Api.Services.Interfaces;

namespace RentFlow.Api.Controllers;

/// <summary>
/// Handles HTTP requests for rental application documents.
/// </summary>
[ApiController]
[Route("api")]
[Authorize]
public class ApplicationDocumentsController(
    IApplicationDocumentService applicationDocumentService,
    IPropertyAccessGuard propertyAccessGuard,
    ICurrentUserService currentUser,
    ILogger<ApplicationDocumentsController> logger) : ControllerBase
{
    [HttpPost("rental-applications/{applicationId:guid}/documents")]
    [Authorize(Roles = nameof(UserRole.Tenant))]
    [Consumes("multipart/form-data")]
    [ProducesResponseType<ApplicationDocumentResponseDto>(StatusCodes.Status201Created)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status409Conflict)]
    public async Task<ActionResult<ApplicationDocumentResponseDto>> Upload(
        Guid applicationId,
        [FromForm] UploadApplicationDocumentDto request,
        CancellationToken cancellationToken)
    {
        await using var content = request.File.OpenReadStream();

        return await ExecuteAsync(
            () => applicationDocumentService.UploadAsync(
                applicationId,
                GetRequiredUserId(),
                request.DocumentType!.Value,
                content,
                request.File.FileName,
                request.File.ContentType,
                request.File.Length,
                cancellationToken),
            result => CreatedAtAction(
                nameof(GetById),
                new { documentId = result.Id },
                result));
    }

    [HttpGet("rental-applications/{applicationId:guid}/documents")]
    [Authorize(Roles = $"{nameof(UserRole.Tenant)},{nameof(UserRole.Landlord)},{nameof(UserRole.Admin)}")]
    [ProducesResponseType<IReadOnlyList<ApplicationDocumentResponseDto>>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    public Task<ActionResult<IReadOnlyList<ApplicationDocumentResponseDto>>> GetByApplication(
        Guid applicationId,
        CancellationToken cancellationToken)
    {
        return ExecuteAsync(
            async () =>
            {
                if (currentUser.Role == UserRole.Tenant)
                {
                    return await applicationDocumentService.GetByApplicationAsync(
                        applicationId, GetRequiredUserId(), cancellationToken);
                }

                await EnsureLandlordCanAccessApplicationAsync(
                    applicationId, cancellationToken);
                return await applicationDocumentService.GetByApplicationForReviewAsync(
                    applicationId, cancellationToken);
            },
            result => Ok(result));
    }

    [HttpGet("application-documents/{documentId:guid}")]
    [Authorize(Roles = $"{nameof(UserRole.Tenant)},{nameof(UserRole.Landlord)},{nameof(UserRole.Admin)}")]
    [ProducesResponseType<ApplicationDocumentResponseDto>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    public Task<ActionResult<ApplicationDocumentResponseDto>> GetById(
        Guid documentId,
        CancellationToken cancellationToken)
    {
        return ExecuteAsync(
            async () => await GetAuthorizedDocumentAsync(documentId, cancellationToken)
                ?? throw ApplicationDocumentServiceException.NotFound(
                    "The application document was not found."),
            result => Ok(result));
    }

    [HttpGet("application-documents/{documentId:guid}/download")]
    [Authorize(Roles = $"{nameof(UserRole.Tenant)},{nameof(UserRole.Landlord)},{nameof(UserRole.Admin)}")]
    [ProducesResponseType(StatusCodes.Status302Found)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    public Task<IActionResult> Download(
        Guid documentId,
        CancellationToken cancellationToken)
    {
        return ExecuteAsync(async () =>
        {
            string signedUrl;
            if (currentUser.Role == UserRole.Tenant)
            {
                signedUrl = await applicationDocumentService.GenerateDownloadUrlAsync(
                    documentId, GetRequiredUserId(), cancellationToken);
            }
            else
            {
                await EnsureLandlordCanAccessDocumentAsync(documentId, cancellationToken);
                signedUrl = await applicationDocumentService.GenerateDownloadUrlForReviewAsync(
                    documentId, cancellationToken);
            }

            return Redirect(signedUrl);
        });
    }

    [HttpDelete("application-documents/{documentId:guid}")]
    [Authorize(Roles = nameof(UserRole.Tenant))]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status409Conflict)]
    public Task<IActionResult> Delete(
        Guid documentId,
        CancellationToken cancellationToken)
    {
        return ExecuteAsync(async () =>
        {
            await applicationDocumentService.DeleteAsync(
                documentId,
                GetRequiredUserId(),
                cancellationToken);
            return NoContent();
        });
    }

    private async Task<ApplicationDocumentResponseDto?> GetAuthorizedDocumentAsync(
        Guid documentId,
        CancellationToken cancellationToken)
    {
        if (currentUser.Role == UserRole.Tenant)
        {
            return await applicationDocumentService.GetByIdAsync(
                documentId, GetRequiredUserId(), cancellationToken);
        }

        await EnsureLandlordCanAccessDocumentAsync(documentId, cancellationToken);
        return await applicationDocumentService.GetByIdForReviewAsync(
            documentId, cancellationToken);
    }

    private async Task EnsureLandlordCanAccessApplicationAsync(
        Guid applicationId,
        CancellationToken cancellationToken)
    {
        if (currentUser.Role == UserRole.Landlord
            && !await propertyAccessGuard.CanAccessApplicationAsync(
                GetRequiredUserId(), applicationId, cancellationToken))
        {
            throw ApplicationDocumentServiceException.NotFound(
                "The rental application was not found.");
        }
    }

    private async Task EnsureLandlordCanAccessDocumentAsync(
        Guid documentId,
        CancellationToken cancellationToken)
    {
        if (currentUser.Role == UserRole.Landlord
            && !await propertyAccessGuard.CanAccessDocumentAsync(
                GetRequiredUserId(), documentId, cancellationToken))
        {
            throw ApplicationDocumentServiceException.NotFound(
                "The application document was not found.");
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
