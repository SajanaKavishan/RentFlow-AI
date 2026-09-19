using RentFlow.Api.DTOs.RentSchedules;

namespace RentFlow.Api.Services.Interfaces;

public interface IRentScheduleService
{
    Task<IReadOnlyList<RentScheduleItemResponseDto>> GenerateForLeaseAsync(
        Guid leaseAgreementId,
        CancellationToken cancellationToken = default);

    Task<IReadOnlyList<RentScheduleItemResponseDto>> GetByLeaseAsync(
        Guid leaseAgreementId,
        CancellationToken cancellationToken = default);

    Task<IReadOnlyList<RentScheduleItemResponseDto>> GetByTenantAsync(
        Guid tenantId,
        CancellationToken cancellationToken = default);

    Task<RentScheduleItemResponseDto?> GetByIdAsync(
        Guid id,
        CancellationToken cancellationToken = default);
}