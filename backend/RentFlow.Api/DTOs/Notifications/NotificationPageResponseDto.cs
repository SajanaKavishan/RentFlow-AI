namespace RentFlow.Api.DTOs.Notifications;

public sealed class NotificationPageResponseDto
{
    public IReadOnlyList<NotificationResponseDto> Items { get; init; } = [];

    public NotificationPaginationDto Pagination { get; init; } = new();
}

public sealed class NotificationPaginationDto
{
    public int Page { get; init; }

    public int PageSize { get; init; }

    public int TotalCount { get; init; }

    public int TotalPages { get; init; }

    public bool HasNextPage { get; init; }

    public bool HasPreviousPage { get; init; }
}