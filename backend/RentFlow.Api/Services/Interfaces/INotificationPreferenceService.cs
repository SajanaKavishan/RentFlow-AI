using RentFlow.Api.DTOs.Notifications;

namespace RentFlow.Api.Services.Interfaces;

public interface INotificationPreferenceService
{
    Task<NotificationPreferencesResponseDto> GetAsync(
        Guid userId,
        CancellationToken cancellationToken = default);

    Task<NotificationPreferencesResponseDto?> UpdateAsync(
        Guid userId,
        UpdateNotificationPreferencesRequestDto request,
        CancellationToken cancellationToken = default);
}
