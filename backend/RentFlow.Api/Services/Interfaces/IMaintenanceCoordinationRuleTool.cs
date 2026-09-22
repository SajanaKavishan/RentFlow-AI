using RentFlow.Api.DTOs.Maintenance;
using RentFlow.Api.Models;

namespace RentFlow.Api.Services.Interfaces;

public interface IMaintenanceCoordinationRuleTool
{
    Task<MaintenanceCoordinationRuleValidationResult> ValidateAsync(
        MaintenanceRequest? request,
        RepairEstimate? estimate = null,
        CancellationToken cancellationToken = default);
}
