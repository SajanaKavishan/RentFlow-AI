namespace RentFlow.Api.Models;

public sealed class TechnicianPasswordSetupToken
{
    public Guid Id { get; set; }

    public Guid UserId { get; set; }

    public Guid CreatedByAdminId { get; set; }

    public string TokenDigest { get; set; } = string.Empty;

    public DateTimeOffset ExpiresAt { get; set; }

    public DateTimeOffset? ConsumedAt { get; set; }

    public DateTimeOffset CreatedAt { get; set; }
}
