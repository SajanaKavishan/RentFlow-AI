namespace RentFlow.Api.Models;

/// <summary>
/// Represents metadata for an image attached to a rental property.
/// The actual image is stored privately in Cloudflare R2.
/// </summary>
public class PropertyImage
{
    public Guid Id { get; set; } = Guid.NewGuid();

    public Guid PropertyId { get; set; }

    public Property Property { get; set; } = null!;

    public string OriginalFileName { get; set; } = string.Empty;

    public string StorageKey { get; set; } = string.Empty;

    public string ContentType { get; set; } = string.Empty;

    public long FileSizeBytes { get; set; }

    public DateTimeOffset UploadedAt { get; set; } = DateTimeOffset.UtcNow;
}