using RentFlow.Api.DTOs.Maintenance;

namespace RentFlow.Api.Services.Interfaces;

/// <summary>
/// Defines core maintenance request operations.
/// </summary>
public interface IMaintenanceRequestService
{
    Task<MaintenanceRequestResponseDto> CreateAsync(
        Guid tenantId,
        CreateMaintenanceRequestDto request,
        CancellationToken cancellationToken = default);

    Task<MaintenanceRequestResponseDto?> GetByIdAsync(
        Guid requestId,
        CancellationToken cancellationToken = default);

    Task<IReadOnlyList<MaintenanceRequestSummaryDto>> GetByTenantAsync(
        Guid tenantId,
        CancellationToken cancellationToken = default);

    Task<IReadOnlyList<MaintenanceRequestSummaryDto>> GetByPropertyAsync(
        Guid propertyId,
        CancellationToken cancellationToken = default);

    Task<MaintenanceRequestResponseDto> UpdateTenantRequestAsync(
        Guid requestId,
        Guid tenantId,
        UpdateMaintenanceRequestDto request,
        CancellationToken cancellationToken = default);

    Task<MaintenanceRequestResponseDto> TriageAsync(
        Guid requestId,
        TriageMaintenanceRequestDto request,
        CancellationToken cancellationToken = default);

    Task<MaintenanceRequestResponseDto> AssignTechnicianAsync(
        Guid requestId,
        AssignTechnicianDto request,
        CancellationToken cancellationToken = default);
}
