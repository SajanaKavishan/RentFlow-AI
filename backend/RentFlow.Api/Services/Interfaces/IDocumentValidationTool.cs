using RentFlow.Api.DTOs.ApplicationValidation;
using RentFlow.Api.Models;

namespace RentFlow.Api.Services.Interfaces;

public interface IDocumentValidationTool
{
    Task<DocumentValidationResult> ValidateAsync(
        IReadOnlyCollection<ApplicationDocument> documents,
        CancellationToken cancellationToken = default);
}
