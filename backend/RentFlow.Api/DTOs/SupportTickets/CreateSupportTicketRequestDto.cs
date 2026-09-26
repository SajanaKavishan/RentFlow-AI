using System.ComponentModel.DataAnnotations;

namespace RentFlow.Api.DTOs.SupportTickets;

public sealed class CreateSupportTicketRequestDto
{
    [Required]
    public string Category { get; init; } = string.Empty;

    [Required]
    [StringLength(200, MinimumLength = 1)]
    public string Subject { get; init; } = string.Empty;

    [Required]
    [StringLength(4000, MinimumLength = 1)]
    public string Message { get; init; } = string.Empty;
}
