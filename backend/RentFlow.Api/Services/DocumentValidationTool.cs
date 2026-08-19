using RentFlow.Api.DTOs.ApplicationValidation;
using RentFlow.Api.Models;
using RentFlow.Api.Services.Interfaces;

namespace RentFlow.Api.Services;

/// <summary>
/// Validates document presence using metadata only.
/// </summary>
public class DocumentValidationTool : IDocumentValidationTool
{
    private static readonly ApplicationDocumentType[] RequiredDocumentTypes =
    [
        ApplicationDocumentType.IdentityDocument,
        ApplicationDocumentType.IncomeProof
    ];

    public Task<DocumentValidationResult> ValidateAsync(
        IReadOnlyCollection<ApplicationDocument> documents,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(documents);
        cancellationToken.ThrowIfCancellationRequested();

        var presentTypes = documents
            .Select(document => document.DocumentType)
            .Distinct()
            .OrderBy(documentType => documentType)
            .ToArray();

        var missingTypes = RequiredDocumentTypes
            .Except(presentTypes)
            .Select(documentType => documentType.ToString())
            .ToArray();

        var warnings = new List<string>();
        if (!presentTypes.Contains(ApplicationDocumentType.EmploymentLetter))
        {
            warnings.Add("EmploymentLetter is recommended when employment evidence is applicable.");
        }

        return Task.FromResult(new DocumentValidationResult
        {
            IsValid = missingTypes.Length == 0,
            PresentDocumentTypes = presentTypes.Select(documentType => documentType.ToString()).ToArray(),
            MissingDocumentTypes = missingTypes,
            Warnings = warnings
        });
    }
}
