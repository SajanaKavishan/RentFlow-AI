using RentFlow.Api.DTOs.Maintenance;
using RentFlow.Api.Models;

namespace RentFlow.Api.Services.Interfaces;

public interface IMaintenanceRequestDataValidationTool
{
    Task<MaintenanceDataValidationResult> ValidateAsync(
        MaintenanceRequest? request,
        CancellationToken cancellationToken = default);
}
