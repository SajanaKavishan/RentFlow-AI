using RentFlow.Api.DTOs.Maintenance;

namespace RentFlow.Api.Services.Interfaces;

public interface IMaintenanceCoordinationService
{
    Task<MaintenanceCoordinationResult> AnalyzeAsync(Guid requestId, CancellationToken cancellationToken = default);
}