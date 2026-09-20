namespace RentFlow.Api.DTOs.Notifications;

public sealed class NotificationResponseDto
{
    public Guid Id { get; init; }

    public string EventType { get; init; } = string.Empty;

    public string RelatedResourceType { get; init; } = string.Empty;

    public Guid RelatedResourceId { get; init; }

    public string Title { get; init; } = string.Empty;

    public string Message { get; init; } = string.Empty;

    public DateTimeOffset CreatedAt { get; init; }

    public DateTimeOffset? ReadAt { get; init; }

    public bool IsRead => ReadAt.HasValue;
}