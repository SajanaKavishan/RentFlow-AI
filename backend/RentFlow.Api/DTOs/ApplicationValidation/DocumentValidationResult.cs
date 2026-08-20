namespace RentFlow.Api.DTOs.ApplicationValidation;

public class DocumentValidationResult
{
    public bool IsValid { get; init; }

    public IReadOnlyCollection<string> PresentDocumentTypes { get; init; } = Array.Empty<string>();

    public IReadOnlyCollection<string> MissingDocumentTypes { get; init; } = Array.Empty<string>();

    public IReadOnlyCollection<string> Warnings { get; init; } = Array.Empty<string>();
}
