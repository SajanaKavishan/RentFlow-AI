using RentFlow.Api.DTOs.SupportTickets;
using RentFlow.Api.Models;

namespace RentFlow.Api.Services.Interfaces;

public interface ISupportTicketService
{
    Task<SupportTicketResponseDto> CreateAsync(
        Guid userId,
        SupportTicketCategory category,
        string subject,
        string message,
        CancellationToken cancellationToken = default);

    Task<IReadOnlyList<SupportTicketResponseDto>> GetMineAsync(
        Guid userId,
        CancellationToken cancellationToken = default);
}
