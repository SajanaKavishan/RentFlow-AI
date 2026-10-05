using RentFlow.Api.Models;

namespace RentFlow.Api.Services;

internal static class NotificationEventFactory
{
    public static Notification ForPasswordChanged(
        ApplicationUser user,
        DateTimeOffset changedAt)
    {
        return new Notification
        {
            Id = Guid.NewGuid(),
            RecipientId = user.Id,
            EventType = NotificationEventTypes.AccountPasswordChanged,
            RelatedResourceType = "UserAccount",
            RelatedResourceId = user.Id,
            Title = "Password changed",
            Message = "Your password was changed successfully.",
            CreatedAt = changedAt
        };
    }

    public static Notification ForPasswordReset(
        ApplicationUser user,
        DateTimeOffset resetAt)
    {
        return new Notification
        {
            Id = Guid.NewGuid(),
            RecipientId = user.Id,
            EventType = NotificationEventTypes.AccountPasswordReset,
            RelatedResourceType = "UserAccount",
            RelatedResourceId = user.Id,
            Title = "Password reset",
            Message = "Your password was reset successfully.",
            CreatedAt = resetAt
        };
    }

    public static Notification ForMaintenanceTechnicianActivation(
        ApplicationUser technician,
        Guid provisioningAdminId,
        DateTimeOffset activatedAt)
    {
        return new Notification
        {
            Id = Guid.NewGuid(),
            RecipientId = provisioningAdminId,
            EventType = NotificationEventTypes.MaintenanceTechnicianActivated,
            RelatedResourceType = "MaintenanceTechnician",
            RelatedResourceId = technician.Id,
            Title = "Technician account activated",
            Message = "The Maintenance Technician account you provisioned is now active.",
            CreatedAt = activatedAt
        };
    }

    public static Notification ForMaintenanceRequestAssigned(
        MaintenanceRequest request,
        Guid technicianId,
        DateTimeOffset assignedAt)
    {
        var reference = string.IsNullOrWhiteSpace(request.ReferenceCode)
            ? MaintenanceReferenceCode.FromId(request.Id)
            : request.ReferenceCode;
        return new Notification
        {
            Id = Guid.NewGuid(),
            RecipientId = technicianId,
            EventType = NotificationEventTypes.MaintenanceRequestAssigned,
            RelatedResourceType = "MaintenanceRequest",
            RelatedResourceId = request.Id,
            Title = "New maintenance job assigned",
            Message = $"{request.Title} ({reference}) has been assigned to you.",
            CreatedAt = assignedAt
        };
    }

    public static Notification ForViewingCreated(
        ViewingRequest viewing,
        Guid landlordId)
    {
        return new Notification
        {
            Id = Guid.NewGuid(),
            RecipientId = landlordId,
            EventType = NotificationEventTypes.ViewingCreated,
            RelatedResourceType = "ViewingRequest",
            RelatedResourceId = viewing.Id,
            Title = "New viewing request",
            Message = "A tenant submitted a viewing request for your property.",
            CreatedAt = DateTimeOffset.UtcNow
        };
    }

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
            EventType = approved
                ? NotificationEventTypes.ViewingApproved
                : NotificationEventTypes.ViewingRejected,
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
                NotificationEventTypes.RentalApplicationApproved,
                "Rental application approved",
                "Your rental application was approved."),
            RentalApplicationStatus.Rejected => (
                NotificationEventTypes.RentalApplicationRejected,
                "Rental application rejected",
                "Your rental application was rejected."),
            RentalApplicationStatus.ChangesRequested => (
                NotificationEventTypes.RentalApplicationChangesRequested,
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

    public static Notification ForRentalApplicationSubmission(
        RentalApplication application,
        Guid landlordId,
        bool isResubmission)
    {
        return new Notification
        {
            Id = Guid.NewGuid(),
            RecipientId = landlordId,
            EventType = isResubmission
                ? NotificationEventTypes.RentalApplicationResubmitted
                : NotificationEventTypes.RentalApplicationSubmitted,
            RelatedResourceType = "RentalApplication",
            RelatedResourceId = application.Id,
            Title = isResubmission
                ? "Rental application resubmitted"
                : "Rental application submitted",
            Message = isResubmission
                ? "A rental application was resubmitted after requested changes."
                : "A rental application was submitted for your property.",
            CreatedAt = DateTimeOffset.UtcNow
        };
    }
}
