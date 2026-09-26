using Microsoft.EntityFrameworkCore;
using RentFlow.Api.Data;
using RentFlow.Api.DTOs.SupportTickets;
using RentFlow.Api.Models;
using RentFlow.Api.Services.Interfaces;

namespace RentFlow.Api.Services;

public sealed class SupportTicketService(
    ApplicationDbContext dbContext,
    TimeProvider timeProvider) : ISupportTicketService
{
    public async Task<SupportTicketResponseDto> CreateAsync(
        Guid userId,
        SupportTicketCategory category,
        string subject,
        string message,
        CancellationToken cancellationToken = default)
    {
        var now = timeProvider.GetUtcNow();
        var ticket = new SupportTicket
        {
            UserId = userId,
            Category = category,
            Subject = subject,
            Message = message,
            Status = SupportTicketStatus.Open,
            CreatedAt = now,
            UpdatedAt = now
        };

        dbContext.SupportTickets.Add(ticket);
        await dbContext.SaveChangesAsync(cancellationToken);
        return ToResponse(ticket);
    }

    public async Task<IReadOnlyList<SupportTicketResponseDto>> GetMineAsync(
        Guid userId,
        CancellationToken cancellationToken = default) =>
        await dbContext.SupportTickets
            .AsNoTracking()
            .Where(ticket => ticket.UserId == userId)
            .OrderByDescending(ticket => ticket.CreatedAt)
            .ThenByDescending(ticket => ticket.Id)
            .Select(ticket => ToResponse(ticket))
            .ToListAsync(cancellationToken);

    private static SupportTicketResponseDto ToResponse(SupportTicket ticket) => new()
    {
        Id = ticket.Id,
        Category = ticket.Category.ToString(),
        Subject = ticket.Subject,
        Message = ticket.Message,
        Status = ticket.Status.ToString(),
        CreatedAt = ticket.CreatedAt,
        UpdatedAt = ticket.UpdatedAt
    };
}
