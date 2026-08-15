using Microsoft.EntityFrameworkCore;
using RentFlow.Api.Data;
using RentFlow.Api.DTOs.ApplicationDocuments;
using RentFlow.Api.Models;
using RentFlow.Api.Services.Interfaces;

namespace RentFlow.Api.Services;

/// <summary>
/// Provides rental application document operations.
/// </summary>
public class ApplicationDocumentService(
    ApplicationDbContext dbContext,
    IFileStorageService fileStorageService,
    ILogger<ApplicationDocumentService> logger) : IApplicationDocumentService
{
    private const long MaximumFileSizeBytes = 5 * 1024 * 1024;
    private static readonly TimeSpan SignedUrlLifetime = TimeSpan.FromMinutes(10);

    private static readonly IReadOnlyDictionary<string, string> AllowedContentTypes =
        new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            ["application/pdf"] = "pdf",
            ["image/jpeg"] = "jpg",
            ["image/png"] = "png"
        };

    public async Task<ApplicationDocumentResponseDto> UploadAsync(
        Guid applicationId,
        Guid tenantId,
        ApplicationDocumentType documentType,
        Stream content,
        string originalFileName,
        string contentType,
        long fileSizeBytes,
        CancellationToken cancellationToken = default)
    {
        ValidateIdentifiers(applicationId, tenantId);
        ValidateUpload(documentType, content, contentType, fileSizeBytes);

        var application = await GetOwnedApplicationAsync(
            applicationId,
            tenantId,
            cancellationToken);

        EnsureDocumentsCanBeChanged(application.Status, "uploaded");

        var normalizedContentType = contentType.Trim().ToLowerInvariant();
        var documentId = Guid.NewGuid();
        var storageKey =
            $"applications/{applicationId:N}/{documentId:N}.{AllowedContentTypes[normalizedContentType]}";

        await fileStorageService.UploadAsync(
            content,
            storageKey,
            normalizedContentType,
            cancellationToken);

        var document = new ApplicationDocument
        {
            Id = documentId,
            ApplicationId = applicationId,
            DocumentType = documentType,
            OriginalFileName = SanitizeFileName(originalFileName),
            StorageKey = storageKey,
            ContentType = normalizedContentType,
            FileSizeBytes = fileSizeBytes,
            UploadedAt = DateTimeOffset.UtcNow
        };

        dbContext.ApplicationDocuments.Add(document);

        try
        {
            await dbContext.SaveChangesAsync(cancellationToken);
        }
        catch
        {
            await TryDeleteOrphanedUploadAsync(storageKey);
            throw;
        }

        return MapToResponse(document);
    }

    public async Task<ApplicationDocumentResponseDto?> GetByIdAsync(
        Guid documentId,
        Guid tenantId,
        CancellationToken cancellationToken = default)
    {
        ValidateDocumentAndTenantIds(documentId, tenantId);

        var document = await GetOwnedDocumentAsync(
            documentId,
            tenantId,
            asTracking: false,
            cancellationToken);

        return document is null ? null : MapToResponse(document);
    }

    public async Task<IReadOnlyList<ApplicationDocumentResponseDto>> GetByApplicationAsync(
        Guid applicationId,
        Guid tenantId,
        CancellationToken cancellationToken = default)
    {
        ValidateIdentifiers(applicationId, tenantId);
        await GetOwnedApplicationAsync(applicationId, tenantId, cancellationToken);

        var documents = await dbContext.ApplicationDocuments
            .AsNoTracking()
            .Where(document => document.ApplicationId == applicationId)
            .OrderByDescending(document => document.UploadedAt)
            .ToListAsync(cancellationToken);

        return documents.Select(MapToResponse).ToList();
    }

    public async Task<string> GenerateDownloadUrlAsync(
        Guid documentId,
        Guid tenantId,
        CancellationToken cancellationToken = default)
    {
        ValidateDocumentAndTenantIds(documentId, tenantId);

        var document = await GetOwnedDocumentAsync(
            documentId,
            tenantId,
            asTracking: false,
            cancellationToken)
            ?? throw DocumentNotFound();

        return await fileStorageService.GenerateSignedGetUrlAsync(
            document.StorageKey,
            SignedUrlLifetime);
    }

    public async Task DeleteAsync(
        Guid documentId,
        Guid tenantId,
        CancellationToken cancellationToken = default)
    {
        ValidateDocumentAndTenantIds(documentId, tenantId);

        var document = await GetOwnedDocumentAsync(
            documentId,
            tenantId,
            asTracking: true,
            cancellationToken)
            ?? throw DocumentNotFound();

        var application = await GetOwnedApplicationAsync(
            document.ApplicationId,
            tenantId,
            cancellationToken);

        EnsureDocumentsCanBeChanged(application.Status, "deleted");

        await using var transaction = await dbContext.Database.BeginTransactionAsync(cancellationToken);

        dbContext.ApplicationDocuments.Remove(document);
        await dbContext.SaveChangesAsync(cancellationToken);

        try
        {
            await fileStorageService.DeleteAsync(document.StorageKey, cancellationToken);
        }
        catch
        {
            await transaction.RollbackAsync(CancellationToken.None);
            throw;
        }

        try
        {
            await transaction.CommitAsync(CancellationToken.None);
        }
        catch (Exception exception)
        {
            logger.LogCritical(
                exception,
                "R2 object {StorageKey} was deleted, but the document database transaction could not be committed. Manual reconciliation may be required.",
                document.StorageKey);
            throw;
        }
    }

    private async Task<RentalApplication> GetOwnedApplicationAsync(
        Guid applicationId,
        Guid tenantId,
        CancellationToken cancellationToken)
    {
        return await dbContext.RentalApplications
            .AsNoTracking()
            .SingleOrDefaultAsync(
                application => application.Id == applicationId
                    && application.TenantId == tenantId,
                cancellationToken)
            ?? throw ApplicationDocumentServiceException.NotFound(
                "The rental application was not found.");
    }

    private async Task<ApplicationDocument?> GetOwnedDocumentAsync(
        Guid documentId,
        Guid tenantId,
        bool asTracking,
        CancellationToken cancellationToken)
    {
        IQueryable<ApplicationDocument> query = dbContext.ApplicationDocuments;
        if (!asTracking)
        {
            query = query.AsNoTracking();
        }

        return await query.SingleOrDefaultAsync(
            document => document.Id == documentId
                && dbContext.RentalApplications.Any(
                    application => application.Id == document.ApplicationId
                        && application.TenantId == tenantId),
            cancellationToken);
    }

    private async Task TryDeleteOrphanedUploadAsync(string storageKey)
    {
        try
        {
            await fileStorageService.DeleteAsync(storageKey, CancellationToken.None);
        }
        catch (Exception exception)
        {
            logger.LogError(
                exception,
                "Document metadata persistence failed and R2 object {StorageKey} could not be removed. Manual cleanup may be required.",
                storageKey);
        }
    }

    private static void ValidateUpload(
        ApplicationDocumentType documentType,
        Stream content,
        string contentType,
        long fileSizeBytes)
    {
        if (!Enum.IsDefined(documentType))
        {
            throw ApplicationDocumentServiceException.Validation(
                "A valid document type is required.");
        }

        if (content is null || !content.CanRead)
        {
            throw ApplicationDocumentServiceException.Validation(
                "A readable document file is required.");
        }

        if (fileSizeBytes <= 0)
        {
            throw ApplicationDocumentServiceException.Validation(
                "The document file cannot be empty.");
        }

        if (fileSizeBytes > MaximumFileSizeBytes)
        {
            throw ApplicationDocumentServiceException.Validation(
                "The document file cannot exceed 5 MB.");
        }

        if (string.IsNullOrWhiteSpace(contentType)
            || !AllowedContentTypes.ContainsKey(contentType.Trim()))
        {
            throw ApplicationDocumentServiceException.Validation(
                "Only PDF, JPEG, and PNG documents are supported.");
        }
    }

    private static void ValidateIdentifiers(Guid applicationId, Guid tenantId)
    {
        if (applicationId == Guid.Empty)
        {
            throw ApplicationDocumentServiceException.Validation(
                "A rental application ID is required.");
        }

        if (tenantId == Guid.Empty)
        {
            throw ApplicationDocumentServiceException.Validation(
                "A tenant ID is required.");
        }
    }

    private static void ValidateDocumentAndTenantIds(Guid documentId, Guid tenantId)
    {
        if (documentId == Guid.Empty)
        {
            throw ApplicationDocumentServiceException.Validation(
                "A document ID is required.");
        }

        if (tenantId == Guid.Empty)
        {
            throw ApplicationDocumentServiceException.Validation(
                "A tenant ID is required.");
        }
    }

    private static void EnsureDocumentsCanBeChanged(
        RentalApplicationStatus status,
        string action)
    {
        if (status is not RentalApplicationStatus.Draft
            and not RentalApplicationStatus.ChangesRequested)
        {
            throw ApplicationDocumentServiceException.Conflict(
                $"Documents cannot be {action} while the rental application is {status}.");
        }
    }

    private static string SanitizeFileName(string originalFileName)
    {
        var normalized = (originalFileName ?? string.Empty).Replace('\\', '/');
        var fileName = normalized[(normalized.LastIndexOf('/') + 1)..];
        fileName = new string(fileName.Where(character => !char.IsControl(character)).ToArray()).Trim();

        if (string.IsNullOrWhiteSpace(fileName))
        {
            fileName = "document";
        }

        return fileName.Length <= 255 ? fileName : fileName[..255];
    }

    private static ApplicationDocumentServiceException DocumentNotFound() =>
        ApplicationDocumentServiceException.NotFound("The application document was not found.");

    private static ApplicationDocumentResponseDto MapToResponse(ApplicationDocument document)
    {
        return new ApplicationDocumentResponseDto
        {
            Id = document.Id,
            ApplicationId = document.ApplicationId,
            DocumentType = document.DocumentType,
            OriginalFileName = document.OriginalFileName,
            ContentType = document.ContentType,
            FileSizeBytes = document.FileSizeBytes,
            UploadedAt = document.UploadedAt
        };
    }
}
