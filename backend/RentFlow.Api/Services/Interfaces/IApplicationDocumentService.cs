using RentFlow.Api.DTOs.ApplicationDocuments;
using RentFlow.Api.Models;

namespace RentFlow.Api.Services.Interfaces;

/// <summary>
/// Defines operations for rental application documents.
/// </summary>
public interface IApplicationDocumentService
{
    Task<ApplicationDocumentResponseDto> UploadAsync(
        Guid applicationId,
        Guid tenantId,
        ApplicationDocumentType documentType,
        Stream content,
        string originalFileName,
        string contentType,
        long fileSizeBytes,
        CancellationToken cancellationToken = default);

    Task<ApplicationDocumentResponseDto?> GetByIdAsync(
        Guid documentId,
        Guid tenantId,
        CancellationToken cancellationToken = default);

    Task<ApplicationDocumentResponseDto?> GetByIdForReviewAsync(
        Guid documentId,
        CancellationToken cancellationToken = default);

    Task<IReadOnlyList<ApplicationDocumentResponseDto>> GetByApplicationAsync(
        Guid applicationId,
        Guid tenantId,
        CancellationToken cancellationToken = default);

    Task<IReadOnlyList<ApplicationDocumentResponseDto>> GetByApplicationForReviewAsync(
        Guid applicationId,
        CancellationToken cancellationToken = default);

    Task<string> GenerateDownloadUrlAsync(
        Guid documentId,
        Guid tenantId,
        CancellationToken cancellationToken = default);

    Task<string> GenerateDownloadUrlForReviewAsync(
        Guid documentId,
        CancellationToken cancellationToken = default);

    Task DeleteAsync(
        Guid documentId,
        Guid tenantId,
        CancellationToken cancellationToken = default);
}
