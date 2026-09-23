using RentFlow.Api.DTOs.Maintenance;

namespace RentFlow.Api.Services.Interfaces;

public interface IMaintenanceCoordinationAgentClient
{
    Task<MaintenanceCoordinationAgentResponse> AnalyzeAsync(
        MaintenanceCoordinationAgentRequest request,
        CancellationToken cancellationToken = default);
}