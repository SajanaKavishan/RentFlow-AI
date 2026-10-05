using RentFlow.Api.DTOs.Viewings;

namespace RentFlow.Api.Services.Interfaces;

/// <summary>
/// Defines operations for the Viewing Booking feature.
/// </summary>
public interface IViewingService
{
    Task<IReadOnlyList<PropertyPendingViewingCountDto>> GetPendingCountsForLandlordAsync(
        Guid landlordId,
        CancellationToken cancellationToken = default);

    Task<ViewingResponseDto> CreateAsync(
        Guid tenantId,
        CreateViewingRequestDto request,
        CancellationToken cancellationToken = default);

    Task<ViewingResponseDto?> GetByIdAsync(
        Guid viewingId,
        CancellationToken cancellationToken = default);

    Task<ViewingResponseDto?> GetByIdForTenantAsync(
        Guid viewingId,
        Guid tenantId,
        CancellationToken cancellationToken = default);

    Task<IReadOnlyList<ViewingResponseDto>> GetByTenantAsync(
        Guid tenantId,
        CancellationToken cancellationToken = default);

    Task<IReadOnlyList<ViewingResponseDto>> GetByPropertyAsync(
        Guid propertyId,
        CancellationToken cancellationToken = default);

    Task<ViewingResponseDto> ApproveAsync(
        Guid viewingId,
        string? landlordResponse = null,
        CancellationToken cancellationToken = default);

    Task<ViewingResponseDto> RejectAsync(
        Guid viewingId,
        string landlordResponse,
        CancellationToken cancellationToken = default);

    Task<ViewingResponseDto> CancelAsync(
        Guid viewingId,
        Guid tenantId,
        CancellationToken cancellationToken = default);

    Task<ViewingResponseDto> CompleteAsync(
        Guid viewingId,
        CancellationToken cancellationToken = default);
}
