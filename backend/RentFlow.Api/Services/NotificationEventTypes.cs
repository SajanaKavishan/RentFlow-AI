namespace RentFlow.Api.Services;

internal static class NotificationEventTypes
{
    public const string ViewingCreated = "viewing.created";
    public const string ViewingApproved = "viewing.approved";
    public const string ViewingRejected = "viewing.rejected";
    public const string RentalApplicationSubmitted = "rental_application.submitted";
    public const string RentalApplicationResubmitted = "rental_application.resubmitted";
    public const string RentalApplicationApproved = "rental_application.approved";
    public const string RentalApplicationRejected = "rental_application.rejected";
    public const string RentalApplicationChangesRequested =
        "rental_application.changes_requested";
    public const string MaintenanceTechnicianActivated =
        "maintenance_technician.activated";
    public const string AccountPasswordChanged = "account.password_changed";
    public const string AccountPasswordReset = "account.password_reset";
    public const string MaintenanceRequestAssigned = "maintenance_request.assigned";
}
