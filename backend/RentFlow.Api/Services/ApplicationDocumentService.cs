using Microsoft.EntityFrameworkCore;
using RentFlow.Api.Data;
using RentFlow.Api.DTOs.ApplicationDocuments;
using RentFlow.Api.Models;
using RentFlow.Api.Services.Interfaces;

namespace RentFlow.Api.Services;

/// <summary>
/// Provides rental application document operations.
/// </summary>
public class ApplicationDocumentService(ApplicationDbContext dbContext) : IApplicationDocumentService
{
    public async Task<ApplicationDocumentResponseDto?> GetByIdAsync(
        Guid documentId,
        CancellationToken cancellationToken = default)
    {
        var document = await dbContext.ApplicationDocuments
            .AsNoTracking()
            .SingleOrDefaultAsync(item => item.Id == documentId, cancellationToken);

        return document is null ? null : MapToResponse(document);
    }

    public async Task<IReadOnlyList<ApplicationDocumentResponseDto>> GetByApplicationAsync(
        Guid applicationId,
        CancellationToken cancellationToken = default)
    {
        var documents = await dbContext.ApplicationDocuments
            .AsNoTracking()
            .Where(document => document.ApplicationId == applicationId)
            .OrderByDescending(document => document.UploadedAt)
            .ToListAsync(cancellationToken);

        return documents.Select(MapToResponse).ToList();
    }

    private static ApplicationDocumentResponseDto MapToResponse(ApplicationDocument document)
    {
        return new ApplicationDocumentResponseDto
        {
            Id = document.Id,
            ApplicationId = document.ApplicationId,
            DocumentType = document.DocumentType,
            OriginalFileName = document.OriginalFileName,
            StorageKey = document.StorageKey,
            ContentType = document.ContentType,
            FileSizeBytes = document.FileSizeBytes,
            UploadedAt = document.UploadedAt
        };
    }
}
