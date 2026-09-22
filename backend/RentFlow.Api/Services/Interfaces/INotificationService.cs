using RentFlow.Api.DTOs.Notifications;

namespace RentFlow.Api.Services.Interfaces;

public interface INotificationService
{
    Task<NotificationPageResponseDto> GetPageAsync(
        Guid recipientId,
        int page,
        int pageSize,
        CancellationToken cancellationToken);

    Task<UnreadNotificationCountResponseDto> GetUnreadCountAsync(
        Guid recipientId,
        CancellationToken cancellationToken);

    Task<NotificationResponseDto?> MarkAsReadAsync(
        Guid recipientId,
        Guid notificationId,
        CancellationToken cancellationToken);
}