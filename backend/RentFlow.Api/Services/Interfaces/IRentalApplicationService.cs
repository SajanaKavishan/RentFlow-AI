using RentFlow.Api.DTOs.RentalApplications;

namespace RentFlow.Api.Services.Interfaces;

/// <summary>
/// Defines operations for rental applications.
/// </summary>
public interface IRentalApplicationService
{
    Task<RentalApplicationEligibilityDto> GetEligibilityAsync(Guid tenantId, Guid propertyId,
        CancellationToken cancellationToken = default);

    Task<IReadOnlyList<EligibleApplicationPropertyDto>> GetEligiblePropertiesAsync(Guid tenantId,
        CancellationToken cancellationToken = default);

    Task<RentalApplicationResponseDto> CreateAsync(
        Guid tenantId,
        CreateRentalApplicationDto request,
        CancellationToken cancellationToken = default);

    Task<RentalApplicationResponseDto?> GetByIdAsync(
        Guid applicationId,
        CancellationToken cancellationToken = default);

    Task<RentalApplicationResponseDto?> GetByIdForTenantAsync(
        Guid applicationId,
        Guid tenantId,
        CancellationToken cancellationToken = default);

    Task<IReadOnlyList<RentalApplicationResponseDto>> GetByTenantAsync(
        Guid tenantId,
        CancellationToken cancellationToken = default);

    Task<IReadOnlyList<RentalApplicationResponseDto>> GetByPropertyAsync(
        Guid propertyId,
        CancellationToken cancellationToken = default);

    Task<RentalApplicationResponseDto> UpdateAsync(
        Guid applicationId,
        Guid tenantId,
        UpdateRentalApplicationDto request,
        CancellationToken cancellationToken = default);

    Task<RentalApplicationResponseDto> SubmitAsync(
        Guid applicationId,
        Guid tenantId,
        CancellationToken cancellationToken = default);

    Task<RentalApplicationResponseDto> MarkUnderReviewAsync(
        Guid applicationId,
        CancellationToken cancellationToken = default);

    Task<RentalApplicationResponseDto> ApproveAsync(
        Guid applicationId,
        string? landlordResponse = null,
        CancellationToken cancellationToken = default);

    Task<RentalApplicationResponseDto> RejectAsync(
        Guid applicationId,
        string landlordReason,
        CancellationToken cancellationToken = default);

    Task<RentalApplicationResponseDto> RequestChangesAsync(
        Guid applicationId,
        string landlordMessage,
        CancellationToken cancellationToken = default);

    Task<RentalApplicationResponseDto> WithdrawAsync(
        Guid applicationId,
        Guid tenantId,
        CancellationToken cancellationToken = default);
}
