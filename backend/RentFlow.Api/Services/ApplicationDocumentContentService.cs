using Microsoft.Extensions.Options;
using RentFlow.Api.Configuration;
using RentFlow.Api.DTOs.ApplicationValidation;
using RentFlow.Api.Models;
using RentFlow.Api.Services.Interfaces;

namespace RentFlow.Api.Services;

public sealed class ApplicationDocumentContentService(
    IFileStorageService fileStorageService,
    IOptions<DocumentAnalysisOptions> options,
    ILogger<ApplicationDocumentContentService> logger) : IApplicationDocumentContentService
{
    private static readonly HashSet<ApplicationDocumentType> SupportedDocumentTypes =
    [
        ApplicationDocumentType.IncomeProof,
        ApplicationDocumentType.EmploymentLetter,
        ApplicationDocumentType.IdentityDocument
    ];

    public async Task<SupportingDocumentPreparationResult> PrepareForAnalysisAsync(
        Guid applicationId,
        ApplicationDocument authorizedDocument,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(authorizedDocument);
        var settings = options.Value;

        if (!settings.Enabled)
        {
            return Excluded(authorizedDocument, "analysis_disabled",
                "Supporting document analysis is disabled.");
        }

        if (applicationId == Guid.Empty || authorizedDocument.ApplicationId != applicationId)
        {
            return Excluded(authorizedDocument, "application_mismatch",
                "The document was excluded because it does not belong to this application.");
        }

        if (!SupportedDocumentTypes.Contains(authorizedDocument.DocumentType))
        {
            return Excluded(authorizedDocument, "unsupported_document_type",
                "The document type is not supported for content analysis.");
        }

        var allowedContentTypes = settings.AllowedContentTypes.ToHashSet(StringComparer.OrdinalIgnoreCase);
        if (!allowedContentTypes.Contains(authorizedDocument.ContentType))
        {
            return Excluded(authorizedDocument, "unsupported_content_type",
                "The document content type is not supported for analysis.");
        }

        if (authorizedDocument.FileSizeBytes <= 0
            || authorizedDocument.FileSizeBytes > settings.MaxFileBytes)
        {
            return Excluded(authorizedDocument, "invalid_file_size",
                "The document exceeds the analysis size limit or has an invalid size.");
        }

        byte[] content;
        try
        {
            content = await fileStorageService.DownloadBytesAsync(
                authorizedDocument.StorageKey,
                settings.MaxFileBytes,
                cancellationToken);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (InvalidDataException exception)
        {
            logger.LogWarning(exception,
                "Application document {DocumentId} exceeded the bounded internal retrieval limit.",
                authorizedDocument.Id);
            return Excluded(authorizedDocument, "content_validation_failed",
                "The retrieved document content failed validation.");
        }
        catch (Exception exception)
        {
            logger.LogWarning(exception,
                "Unable to retrieve application document {DocumentId} for internal analysis.",
                authorizedDocument.Id);
            return Excluded(authorizedDocument, "retrieval_failed",
                "The document content could not be prepared for analysis.");
        }

        if (content.LongLength == 0
            || content.LongLength > settings.MaxFileBytes
            || content.LongLength != authorizedDocument.FileSizeBytes)
        {
            return Excluded(authorizedDocument, "content_validation_failed",
                "The retrieved document content failed validation.");
        }

        return new SupportingDocumentPreparationResult
        {
            DocumentId = authorizedDocument.Id,
            Input = new SupportingDocumentAnalysisInput
            {
                DocumentId = authorizedDocument.Id,
                DocumentType = authorizedDocument.DocumentType,
                OriginalFileName = authorizedDocument.OriginalFileName,
                ContentType = authorizedDocument.ContentType,
                SizeBytes = content.LongLength,
                ContentBase64 = Convert.ToBase64String(content)
            }
        };
    }

    private static SupportingDocumentPreparationResult Excluded(
        ApplicationDocument document,
        string code,
        string warning) => new()
        {
            DocumentId = document.Id,
            WarningCode = code,
            Warning = warning
        };
}
