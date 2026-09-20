using RentFlow.Api.Models;

namespace RentFlow.Api.Services;

internal static class NotificationEventFactory
{
    public static Notification ForViewing(
        ViewingRequest viewing,
        ViewingStatus status)
    {
        var approved = status == ViewingStatus.Approved;
        var response = string.IsNullOrWhiteSpace(viewing.LandlordResponse)
            ? string.Empty
            : $" Response: {viewing.LandlordResponse}";

        return new Notification
        {
            Id = Guid.NewGuid(),
            RecipientId = viewing.TenantId,
            EventType = approved ? "viewing.approved" : "viewing.rejected",
            RelatedResourceType = "ViewingRequest",
            RelatedResourceId = viewing.Id,
            Title = approved ? "Viewing approved" : "Viewing rejected",
            Message = approved
                ? $"Your viewing request was approved.{response}"
                : $"Your viewing request was rejected.{response}",
            CreatedAt = DateTimeOffset.UtcNow
        };
    }

    public static Notification ForRentalApplication(
        RentalApplication application,
        RentalApplicationStatus status)
    {
        var (eventType, title, message) = status switch
        {
            RentalApplicationStatus.Approved => (
                "rental_application.approved",
                "Rental application approved",
                "Your rental application was approved."),
            RentalApplicationStatus.Rejected => (
                "rental_application.rejected",
                "Rental application rejected",
                "Your rental application was rejected."),
            RentalApplicationStatus.ChangesRequested => (
                "rental_application.changes_requested",
                "Changes requested for rental application",
                "Changes were requested for your rental application."),
            _ => throw new ArgumentOutOfRangeException(nameof(status), status, null)
        };

        var response = string.IsNullOrWhiteSpace(application.LandlordResponse)
            ? string.Empty
            : $" Response: {application.LandlordResponse}";

        return new Notification
        {
            Id = Guid.NewGuid(),
            RecipientId = application.TenantId,
            EventType = eventType,
            RelatedResourceType = "RentalApplication",
            RelatedResourceId = application.Id,
            Title = title,
            Message = message + response,
            CreatedAt = DateTimeOffset.UtcNow
        };
    }
}