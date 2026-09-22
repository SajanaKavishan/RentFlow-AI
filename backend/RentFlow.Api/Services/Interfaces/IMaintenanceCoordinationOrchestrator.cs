using RentFlow.Api.Models;

namespace RentFlow.Api.Services.Interfaces;

public interface IMaintenanceCoordinationOrchestrator
{
    Task<MaintenanceCoordinationWorkflow> StartAsync(
        Guid maintenanceRequestId,
        CancellationToken cancellationToken = default);

    Task<MaintenanceCoordinationWorkflow> StartAnalysisAsync(
        Guid maintenanceRequestId,
        CancellationToken cancellationToken = default);

    Task<MaintenanceCoordinationWorkflow?> GetByIdAsync(
        Guid workflowId,
        CancellationToken cancellationToken = default);

    Task<MaintenanceCoordinationWorkflow> ApproveAsync(
        Guid workflowId,
        Guid reviewerUserId,
        string? decisionNotes,
        CancellationToken cancellationToken = default);

    Task<MaintenanceCoordinationWorkflow> RejectAsync(
        Guid workflowId,
        Guid reviewerUserId,
        string? decisionNotes,
        CancellationToken cancellationToken = default);
}
