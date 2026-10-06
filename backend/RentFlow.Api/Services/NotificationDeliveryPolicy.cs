using Microsoft.EntityFrameworkCore;
using RentFlow.Api.Data;
using RentFlow.Api.Models;
using System.Security.Cryptography;
using System.Text;

namespace RentFlow.Api.Services;

internal static class NotificationDeliveryPolicy
{
    public static async Task QueueAsync(
        ApplicationDbContext dbContext,
        Notification notification,
        CancellationToken cancellationToken)
    {
        var category = GetCategory(notification.EventType);
        if (category is NotificationCategory.AccountSecurity or NotificationCategory.LandlordAction
            || await IsOptionalCategoryEnabledAsync(
                dbContext,
                notification.RecipientId,
                category,
                cancellationToken))
        {
            dbContext.Notifications.Add(notification);
        }
    }

    // A source transition has a stable primary key, so retries cannot produce duplicate rows.
    // These operational events have no optional category preference in the current contract.
    public static async Task QueueLandlordActionAsync(ApplicationDbContext db, Guid propertyId, string eventType,
        string resourceType, Guid resourceId, Guid sourceEventId, string title, string message, CancellationToken ct)
    {
        var recipient = await db.Properties.AsNoTracking().Where(p => p.Id == propertyId).Select(p => (Guid?)p.LandlordId).SingleOrDefaultAsync(ct);
        if (recipient is null) return;
        var digest = SHA256.HashData(Encoding.UTF8.GetBytes($"{recipient}:{eventType}:{sourceEventId}"));
        var id = new Guid(digest.AsSpan(0, 16));
        if (db.Notifications.Local.Any(n => n.Id == id) || await db.Notifications.AnyAsync(n => n.Id == id, ct)) return;
        await QueueAsync(db, new Notification { Id = id, RecipientId = recipient.Value, EventType = eventType,
            RelatedResourceType = resourceType, RelatedResourceId = resourceId, Title = title, Message = message, CreatedAt = DateTimeOffset.UtcNow }, ct);
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
        NotificationEventTypes.MaintenanceSubmitted or NotificationEventTypes.MaintenanceTriaged
            or NotificationEventTypes.MaintenanceEstimatePreparation or NotificationEventTypes.MaintenanceEstimateReview
            or NotificationEventTypes.MaintenanceCoordinationReview or NotificationEventTypes.LeaseCreationRequired
            or NotificationEventTypes.LeaseActivationRequired or NotificationEventTypes.ManualPaymentReview => NotificationCategory.LandlordAction,
        NotificationEventTypes.ViewingCreated
            or NotificationEventTypes.ViewingApproved
            or NotificationEventTypes.ViewingRejected => NotificationCategory.Viewing,
        NotificationEventTypes.RentalApplicationSubmitted
            or NotificationEventTypes.RentalApplicationResubmitted
            or NotificationEventTypes.RentalApplicationApproved
            or NotificationEventTypes.RentalApplicationRejected
            or NotificationEventTypes.RentalApplicationChangesRequested =>
                NotificationCategory.RentalApplication,
        NotificationEventTypes.MaintenanceTechnicianActivated
            or NotificationEventTypes.AccountPasswordChanged
            or NotificationEventTypes.AccountPasswordReset =>
            NotificationCategory.AccountSecurity,
        _ => throw new InvalidOperationException(
            $"Notification event type '{eventType}' has no delivery category.")
    };

    private enum NotificationCategory
    {
        Viewing,
        RentalApplication,
        AccountSecurity,
        LandlordAction
    }
}
