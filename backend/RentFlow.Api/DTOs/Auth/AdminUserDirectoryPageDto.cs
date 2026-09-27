using RentFlow.Api.Models;

namespace RentFlow.Api.DTOs.Auth;

public sealed record AdminUserDirectoryItemDto(
    Guid Id,
    string FullName,
    string Email,
    UserRole Role,
    bool IsActive,
    DateTimeOffset CreatedAt);

public sealed class AdminUserDirectoryPageDto
{
    public IReadOnlyList<AdminUserDirectoryItemDto> Items { get; init; } = [];

    public AdminUserDirectoryPaginationDto Pagination { get; init; } = new();
}

public sealed class AdminUserDirectoryPaginationDto
{
    public int Page { get; init; }

    public int PageSize { get; init; }

    public int TotalCount { get; init; }

    public int TotalPages { get; init; }

    public bool HasNextPage { get; init; }

    public bool HasPreviousPage { get; init; }
}
