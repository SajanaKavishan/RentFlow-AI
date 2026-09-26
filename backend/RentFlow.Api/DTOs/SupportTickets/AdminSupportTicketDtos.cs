using System.ComponentModel.DataAnnotations;

namespace RentFlow.Api.DTOs.SupportTickets;

public sealed record AdminSupportTicketListItemDto(
    Guid Id,
    string Category,
    string Subject,
    string Status,
    DateTimeOffset CreatedAt,
    string RequesterFullName,
    string RequesterEmail);

public sealed record AdminSupportTicketDetailDto(
    Guid Id,
    string Category,
    string Subject,
    string Message,
    string Status,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt,
    string RequesterFullName,
    string RequesterEmail);

public sealed class AdminSupportTicketPageDto
{
    public IReadOnlyList<AdminSupportTicketListItemDto> Items { get; init; } = [];

    public AdminSupportTicketPaginationDto Pagination { get; init; } = new();
}

public sealed class AdminSupportTicketPaginationDto
{
    public int Page { get; init; }

    public int PageSize { get; init; }

    public int TotalCount { get; init; }

    public int TotalPages { get; init; }

    public bool HasNextPage { get; init; }

    public bool HasPreviousPage { get; init; }
}

public sealed class UpdateSupportTicketStatusRequestDto
{
    [Required]
    public string Status { get; init; } = string.Empty;
}

public sealed record AdminSupportTicketStatusResponseDto(
    Guid Id,
    string Status,
    DateTimeOffset UpdatedAt);
