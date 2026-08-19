namespace RentFlow.Api.Models;

public enum ApplicationValidationWorkflowStatus
{
    Pending,
    Running,
    AwaitingHumanReview,
    Completed,
    Failed
}
