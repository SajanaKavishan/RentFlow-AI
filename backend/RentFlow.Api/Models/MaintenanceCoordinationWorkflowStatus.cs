namespace RentFlow.Api.Models;

public enum MaintenanceCoordinationWorkflowStatus
{
    Pending,
    Running,
    AwaitingHumanReview,
    Completed,
    Failed
}
