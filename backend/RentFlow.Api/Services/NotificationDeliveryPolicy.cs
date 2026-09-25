using Microsoft.EntityFrameworkCore;
using RentFlow.Api.Data;
using RentFlow.Api.Models;

namespace RentFlow.Api.Services;

internal static class NotificationDeliveryPolicy
{
    public static async Task QueueAsync(
        ApplicationDbContext dbContext,
        Notification notification,
        CancellationToken cancellationToken)
    {
        var category = GetCategory(notification.EventType);
        if (category == NotificationCategory.AccountSecurity
            || await IsOptionalCategoryEnabledAsync(
                dbContext,
                notification.RecipientId,
                category,
                cancellationToken))
        {
            dbContext.Notifications.Add(notification);
        }
    }

    private static async Task<bool> IsOptionalCategoryEnabledAsync(
        ApplicationDbContext dbContext,
        Guid recipientId,
        NotificationCategory category,
        CancellationToken cancellationToken)
    {
        var preference = await dbContext.NotificationPreferences
            .AsNoTracking()
            .SingleOrDefaultAsync(item => item.UserId == recipientId, cancellationToken);

        return category switch
        {
            NotificationCategory.Viewing => preference?.ViewingUpdatesEnabled ?? true,
            NotificationCategory.RentalApplication =>
                preference?.RentalApplicationUpdatesEnabled ?? true,
            _ => throw new ArgumentOutOfRangeException(nameof(category), category, null)
        };
    }

    private static NotificationCategory GetCategory(string eventType) => eventType switch
    {
        NotificationEventTypes.ViewingCreated
            or NotificationEventTypes.ViewingApproved
            or NotificationEventTypes.ViewingRejected => NotificationCategory.Viewing,
        NotificationEventTypes.RentalApplicationSubmitted
            or NotificationEventTypes.RentalApplicationResubmitted
            or NotificationEventTypes.RentalApplicationApproved
            or NotificationEventTypes.RentalApplicationRejected
            or NotificationEventTypes.RentalApplicationChangesRequested =>
                NotificationCategory.RentalApplication,
        NotificationEventTypes.MaintenanceTechnicianActivated =>
            NotificationCategory.AccountSecurity,
        _ => throw new InvalidOperationException(
            $"Notification event type '{eventType}' has no delivery category.")
    };

    private enum NotificationCategory
    {
        Viewing,
        RentalApplication,
        AccountSecurity
    }
}
