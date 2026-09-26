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

    Task<IReadOnlyList<MaintenanceRequestSummaryDto>> GetByTechnicianAsync(
        Guid technicianId,
        CancellationToken cancellationToken = default);

    Task<IReadOnlyList<MaintenanceStatusHistoryResponseDto>> GetHistoryAsync(
        Guid requestId,
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

    Task<MaintenanceRequestResponseDto> MarkEstimatePendingAsync(
        Guid requestId,
        CancellationToken cancellationToken = default);

    Task<RepairEstimateResponseDto> SubmitEstimateAsync(
        Guid requestId,
        Guid technicianId,
        SubmitRepairEstimateDto request,
        CancellationToken cancellationToken = default);

    Task<MaintenanceRequestResponseDto> SubmitEstimateForReviewAsync(
        Guid requestId,
        Guid estimateId,
        CancellationToken cancellationToken = default);

    Task<RepairEstimateResponseDto> ApproveEstimateAsync(
        Guid requestId,
        Guid estimateId,
        Guid landlordId,
        ReviewRepairEstimateDto request,
        CancellationToken cancellationToken = default);

    Task<RepairEstimateResponseDto> RejectEstimateAsync(
        Guid requestId,
        Guid estimateId,
        Guid landlordId,
        ReviewRepairEstimateDto request,
        CancellationToken cancellationToken = default);

    Task<RepairEstimateResponseDto> RequestEstimateRevisionAsync(
        Guid requestId,
        Guid estimateId,
        Guid landlordId,
        ReviewRepairEstimateDto request,
        CancellationToken cancellationToken = default);

    Task<MaintenanceRequestResponseDto> StartWorkAsync(
        Guid requestId,
        Guid technicianId,
        CancellationToken cancellationToken = default);

    Task<MaintenanceRequestResponseDto> CompleteWorkAsync(
        Guid requestId,
        Guid technicianId,
        CancellationToken cancellationToken = default);

    Task<IReadOnlyList<RepairEstimateResponseDto>> GetEstimatesAsync(
        Guid requestId,
        CancellationToken cancellationToken = default);

    Task<RepairEstimateResponseDto?> GetLatestEstimateAsync(
        Guid requestId,
        CancellationToken cancellationToken = default);
}
