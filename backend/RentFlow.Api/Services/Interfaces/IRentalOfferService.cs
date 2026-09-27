using RentFlow.Api.DTOs.RentalOffers;

namespace RentFlow.Api.Services.Interfaces;

public interface IRentalOfferService
{
    Task<RentalOfferResponseDto> CreateAsync(
        CreateRentalOfferDto dto,
        CancellationToken cancellationToken = default);

    Task<RentalOfferResponseDto?> GetByIdAsync(
        Guid id,
        CancellationToken cancellationToken = default);

    Task<RentalOfferResponseDto?> RefreshExpiredByIdAsync(
        Guid id,
        CancellationToken cancellationToken = default);

    Task<IReadOnlyList<RentalOfferResponseDto>> GetByTenantAsync(
        Guid tenantId,
        CancellationToken cancellationToken = default);

    Task<IReadOnlyList<RentalOfferResponseDto>> GetByLandlordAsync(
        Guid landlordId,
        CancellationToken cancellationToken = default);

    Task<RentalOfferResponseDto> AcceptAsync(
        Guid offerId,
        Guid tenantId,
        CancellationToken cancellationToken = default);

    Task<RentalOfferResponseDto> RejectAsync(
        Guid offerId,
        Guid tenantId,
        CancellationToken cancellationToken = default);

    Task<RentalOfferResponseDto> WithdrawAsync(
        Guid offerId,
        CancellationToken cancellationToken = default);
}
