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
}
