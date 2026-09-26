namespace RentFlow.Api.DTOs.Notifications;

public sealed class NotificationPreferencesResponseDto
{
    public bool ViewingUpdatesEnabled { get; init; }

    public bool RentalApplicationUpdatesEnabled { get; init; }

    public bool AccountSecurityUpdatesEnabled { get; init; } = true;
}
