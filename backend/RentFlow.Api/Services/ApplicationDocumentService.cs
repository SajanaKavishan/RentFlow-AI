using RentFlow.Api.DTOs.ApplicationDocuments;
using RentFlow.Api.Services.Interfaces;

namespace RentFlow.Api.Services;

/// <summary>
/// Placeholder for rental application document operations.
/// </summary>
public class ApplicationDocumentService : IApplicationDocumentService
{
    public Task<ApplicationDocumentResponseDto?> GetByIdAsync(
        Guid documentId,
        CancellationToken cancellationToken = default)
    {
        throw new NotImplementedException(
            "Application document persistence has not been implemented yet.");
    }

    public Task<IReadOnlyList<ApplicationDocumentResponseDto>> GetByApplicationAsync(
        Guid applicationId,
        CancellationToken cancellationToken = default)
    {
        throw new NotImplementedException(
            "Application document persistence has not been implemented yet.");
    }
}
