using RentFlow.Api.DTOs.PropertyMatching;

namespace RentFlow.Api.Services.Interfaces;

public interface ITenantPropertyFavoriteService
{
    Task<TenantPropertyFavoritesResponse> GetAsync(
        Guid tenantId,
        CancellationToken cancellationToken = default);

    Task<bool> AddAsync(
        Guid tenantId,
        Guid propertyId,
        CancellationToken cancellationToken = default);

    Task RemoveAsync(
        Guid tenantId,
        Guid propertyId,
        CancellationToken cancellationToken = default);
}
