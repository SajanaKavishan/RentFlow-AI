namespace RentFlow.Api.Models;

/// <summary>
/// Metadata for a private file attached to a maintenance request.
/// </summary>
public class MaintenanceAttachment
{
    public Guid Id { get; set; } = Guid.NewGuid();

    public Guid MaintenanceRequestId { get; set; }

    public string StorageKey { get; set; } = string.Empty;

    public string FileName { get; set; } = string.Empty;

    public string ContentType { get; set; } = string.Empty;

    public long FileSize { get; set; }

    public string? AttachmentType { get; set; }

    public Guid UploadedByUserId { get; set; }

    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
}
