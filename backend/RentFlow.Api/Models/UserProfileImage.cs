namespace RentFlow.Api.Models;

public sealed class UserProfileImage
{
    public Guid UserId { get; set; }

    public string StorageKey { get; set; } = string.Empty;

    public string ContentType { get; set; } = string.Empty;

    public long FileSizeBytes { get; set; }

    public DateTimeOffset UpdatedAt { get; set; }

    public ApplicationUser User { get; set; } = null!;
}
