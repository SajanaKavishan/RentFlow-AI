namespace RentFlow.Api.Models;

public sealed class Notification
{
    public Guid Id { get; set; }

    public Guid RecipientId { get; set; }

    public string EventType { get; set; } = string.Empty;

    public string RelatedResourceType { get; set; } = string.Empty;

    public Guid RelatedResourceId { get; set; }

    public string Title { get; set; } = string.Empty;

    public string Message { get; set; } = string.Empty;

    public DateTimeOffset CreatedAt { get; set; }

    public DateTimeOffset? ReadAt { get; set; }
}