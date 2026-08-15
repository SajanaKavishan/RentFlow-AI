namespace RentFlow.Api.Models;

/// <summary>
/// Identifies the kind of supporting document attached to a rental application.
/// </summary>
public enum ApplicationDocumentType
{
    IdentityDocument,
    IncomeProof,
    EmploymentLetter,
    Other
}
