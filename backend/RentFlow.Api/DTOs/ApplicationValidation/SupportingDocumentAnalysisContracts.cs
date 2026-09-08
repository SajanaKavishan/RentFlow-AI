using System.Text.Json.Serialization;
using RentFlow.Api.Models;

namespace RentFlow.Api.DTOs.ApplicationValidation;

public sealed class SupportingDocumentAnalysisInput
{
    public Guid DocumentId { get; init; }

    [JsonConverter(typeof(JsonStringEnumConverter))]
    public ApplicationDocumentType DocumentType { get; init; }

    public string OriginalFileName { get; init; } = string.Empty;

    public string ContentType { get; init; } = string.Empty;

    public long SizeBytes { get; init; }

    public string ContentBase64 { get; init; } = string.Empty;
}

public sealed class SupportingDocumentPreparationResult
{
    public Guid DocumentId { get; init; }

    public SupportingDocumentAnalysisInput? Input { get; init; }

    public string? WarningCode { get; init; }

    public string? Warning { get; init; }
}
