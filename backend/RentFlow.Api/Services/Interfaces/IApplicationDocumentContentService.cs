using RentFlow.Api.DTOs.ApplicationValidation;
using RentFlow.Api.Models;

namespace RentFlow.Api.Services.Interfaces;

public interface IApplicationDocumentContentService
{
    Task<SupportingDocumentPreparationResult> PrepareForAnalysisAsync(
        Guid applicationId,
        ApplicationDocument authorizedDocument,
        CancellationToken cancellationToken = default);
}
