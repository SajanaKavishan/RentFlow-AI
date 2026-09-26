namespace RentFlow.Api.DTOs.SupportTickets;

public sealed class SupportTicketResponseDto
{
    public Guid Id { get; init; }

    public string Category { get; init; } = string.Empty;

    public string Subject { get; init; } = string.Empty;

    public string Message { get; init; } = string.Empty;

    public string Status { get; init; } = string.Empty;

    public DateTimeOffset CreatedAt { get; init; }

    public DateTimeOffset UpdatedAt { get; init; }
}
