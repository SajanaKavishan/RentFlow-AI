using RentFlow.Api.DTOs.RentSchedules;
using RentFlow.Api.Models;

namespace RentFlow.Api.Services.Interfaces;

public interface IRentScheduleService
{
    Task<bool> CanAccessLeaseAsync(
        Guid leaseAgreementId,
        Guid? userId,
        UserRole? role,
        CancellationToken cancellationToken = default);

    Task<bool> CanAccessScheduleItemAsync(
        Guid scheduleItemId,
        Guid? userId,
        UserRole? role,
        CancellationToken cancellationToken = default);

    Task<IReadOnlyList<RentScheduleItemResponseDto>> GenerateForLeaseAsync(
        Guid leaseAgreementId,
        CancellationToken cancellationToken = default);

    Task<IReadOnlyList<RentScheduleItemResponseDto>> GetByLeaseAsync(
        Guid leaseAgreementId,
        CancellationToken cancellationToken = default);

    Task<IReadOnlyList<RentScheduleItemResponseDto>> GetByTenantAsync(
        Guid tenantId,
        CancellationToken cancellationToken = default);

    Task<RentScheduleOutstandingSummaryDto> GetOutstandingByLeaseAsync(
        Guid leaseAgreementId,
        CancellationToken cancellationToken = default);

    Task<RentScheduleOutstandingSummaryDto> GetOutstandingByTenantAsync(
        Guid tenantId,
        CancellationToken cancellationToken = default);

    Task<RentScheduleItemResponseDto?> GetByIdAsync(
        Guid id,
        CancellationToken cancellationToken = default);
}
