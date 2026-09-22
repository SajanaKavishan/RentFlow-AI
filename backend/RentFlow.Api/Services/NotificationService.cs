using Microsoft.EntityFrameworkCore;
using RentFlow.Api.Data;
using RentFlow.Api.DTOs.Notifications;
using RentFlow.Api.Models;
using RentFlow.Api.Services.Interfaces;

namespace RentFlow.Api.Services;

public sealed class NotificationService(ApplicationDbContext dbContext) : INotificationService
{
    public async Task<NotificationPageResponseDto> GetPageAsync(
        Guid recipientId,
        int page,
        int pageSize,
        CancellationToken cancellationToken)
    {
        var totalCount = await dbContext.Notifications
            .CountAsync(notification => notification.RecipientId == recipientId, cancellationToken);
        var totalPages = totalCount == 0
            ? 0
            : (int)Math.Ceiling(totalCount / (double)pageSize);

        var notifications = await dbContext.Notifications
            .AsNoTracking()
            .Where(notification => notification.RecipientId == recipientId)
            .OrderByDescending(notification => notification.CreatedAt)
            .ThenByDescending(notification => notification.Id)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(notification => ToResponse(notification))
            .ToListAsync(cancellationToken);

        return new NotificationPageResponseDto
        {
            Items = notifications,
            Pagination = new NotificationPaginationDto
            {
                Page = page,
                PageSize = pageSize,
                TotalCount = totalCount,
                TotalPages = totalPages,
                HasNextPage = page < totalPages,
                HasPreviousPage = page > 1 && totalPages > 0
            }
        };
    }

    public async Task<UnreadNotificationCountResponseDto> GetUnreadCountAsync(
        Guid recipientId,
        CancellationToken cancellationToken)
    {
        var unreadCount = await dbContext.Notifications
            .CountAsync(notification =>
                notification.RecipientId == recipientId && notification.ReadAt == null,
                cancellationToken);

        return new UnreadNotificationCountResponseDto { UnreadCount = unreadCount };
    }

    public async Task<NotificationResponseDto?> MarkAsReadAsync(
        Guid recipientId,
        Guid notificationId,
        CancellationToken cancellationToken)
    {
        var notification = await dbContext.Notifications
            .FirstOrDefaultAsync(item =>
                item.Id == notificationId && item.RecipientId == recipientId,
                cancellationToken);

        if (notification is null)
        {
            return null;
        }

        notification.ReadAt ??= DateTimeOffset.UtcNow;
        await dbContext.SaveChangesAsync(cancellationToken);

        return ToResponse(notification);
    }

    private static NotificationResponseDto ToResponse(Notification notification) => new()
    {
        Id = notification.Id,
        EventType = notification.EventType,
        RelatedResourceType = notification.RelatedResourceType,
        RelatedResourceId = notification.RelatedResourceId,
        Title = notification.Title,
        Message = notification.Message,
        CreatedAt = notification.CreatedAt,
        ReadAt = notification.ReadAt
    };
}