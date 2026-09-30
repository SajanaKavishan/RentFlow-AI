namespace RentFlow.Api.DTOs;

public class PropertyImageResponseDto
{
    public Guid Id { get; set; }

    public Guid PropertyId { get; set; }

    public string OriginalFileName { get; set; } = string.Empty;

    public string ContentType { get; set; } = string.Empty;

    public long FileSizeBytes { get; set; }

    public bool IsPrimary { get; set; }

    public int SortOrder { get; set; }

    public DateTimeOffset UploadedAt { get; set; }
}
