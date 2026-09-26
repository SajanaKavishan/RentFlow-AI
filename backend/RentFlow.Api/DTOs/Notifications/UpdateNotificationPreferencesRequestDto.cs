namespace RentFlow.Api.DTOs.Notifications;

public sealed class UpdateNotificationPreferencesRequestDto
{
    public bool ViewingUpdatesEnabled { get; init; } = true;

    public bool RentalApplicationUpdatesEnabled { get; init; } = true;

    public bool AccountSecurityUpdatesEnabled { get; init; } = true;
}
