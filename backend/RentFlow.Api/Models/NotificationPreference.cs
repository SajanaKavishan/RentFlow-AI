namespace RentFlow.Api.Models;

public sealed class NotificationPreference
{
    public Guid UserId { get; set; }

    public bool ViewingUpdatesEnabled { get; set; } = true;

    public bool RentalApplicationUpdatesEnabled { get; set; } = true;
}
