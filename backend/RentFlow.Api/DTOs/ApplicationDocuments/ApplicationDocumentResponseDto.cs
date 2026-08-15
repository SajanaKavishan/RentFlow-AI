using RentFlow.Api.Models;

namespace RentFlow.Api.DTOs.ApplicationDocuments;

/// <summary>
/// Represents application document metadata returned by the API.
/// </summary>
public class ApplicationDocumentResponseDto
{
    public Guid Id { get; set; }

    public Guid ApplicationId { get; set; }

    public ApplicationDocumentType DocumentType { get; set; }

    public string OriginalFileName { get; set; } = string.Empty;

    public string FileUrl { get; set; } = string.Empty;

    public string ContentType { get; set; } = string.Empty;

    public long FileSizeBytes { get; set; }

    public DateTimeOffset UploadedAt { get; set; }
}
