using RentFlow.Api.DTOs.LeaseAgreements;

namespace RentFlow.Api.Services.Interfaces;

public interface ILeaseAgreementService
{
    Task<LeaseAgreementResponseDto> CreateAsync(
        CreateLeaseAgreementDto dto,
        CancellationToken cancellationToken = default);

    Task<LeaseAgreementResponseDto?> GetByIdAsync(
        Guid id,
        CancellationToken cancellationToken = default);

    Task<IReadOnlyList<LeaseAgreementResponseDto>> GetByTenantAsync(
        Guid tenantId,
        CancellationToken cancellationToken = default);

    Task<IReadOnlyList<LeaseAgreementResponseDto>> GetByLandlordAsync(
        Guid landlordId,
        CancellationToken cancellationToken = default);

    Task<LeaseAgreementResponseDto> ActivateAsync(
        Guid leaseId,
        CancellationToken cancellationToken = default);

    Task<LeaseAgreementResponseDto> TerminateAsync(
        Guid leaseId,
        CancellationToken cancellationToken = default);

    Task<LeaseAgreementResponseDto> CompleteAsync(
        Guid leaseId,
        CancellationToken cancellationToken = default);
}
