using RentFlow.Api.DTOs.ApplicationDocuments;

namespace RentFlow.Api.Services.Interfaces;

/// <summary>
/// Defines operations for rental application documents.
/// </summary>
public interface IApplicationDocumentService
{
    Task<ApplicationDocumentResponseDto?> GetByIdAsync(
        Guid documentId,
        CancellationToken cancellationToken = default);

    Task<IReadOnlyList<ApplicationDocumentResponseDto>> GetByApplicationAsync(
        Guid applicationId,
        CancellationToken cancellationToken = default);
}
