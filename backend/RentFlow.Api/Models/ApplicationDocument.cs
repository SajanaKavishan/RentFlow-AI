namespace RentFlow.Api.Models;

/// <summary>
/// Represents metadata for a document attached to a rental application.
/// </summary>
public class ApplicationDocument
{
    public Guid Id { get; set; } = Guid.NewGuid();

    public Guid ApplicationId { get; set; }

    public ApplicationDocumentType DocumentType { get; set; }

    public string OriginalFileName { get; set; } = string.Empty;

    public string FileUrl { get; set; } = string.Empty;

    public string ContentType { get; set; } = string.Empty;

    public long FileSizeBytes { get; set; }

    public DateTimeOffset UploadedAt { get; set; } = DateTimeOffset.UtcNow;
}
