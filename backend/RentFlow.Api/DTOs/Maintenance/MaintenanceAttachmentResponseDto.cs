namespace RentFlow.Api.DTOs.Maintenance;

/// <summary>
/// Safe maintenance attachment metadata. Storage keys are never exposed.
/// </summary>
public class MaintenanceAttachmentResponseDto
{
    public Guid Id { get; set; }
    public Guid MaintenanceRequestId { get; set; }
    public string FileName { get; set; } = string.Empty;
    public string ContentType { get; set; } = string.Empty;
    public long FileSize { get; set; }
    public string? AttachmentType { get; set; }
    public Guid UploadedByUserId { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
}
