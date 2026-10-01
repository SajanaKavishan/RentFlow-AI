using RentFlow.Api.DTOs.PropertyMatching;

namespace RentFlow.Api.Services.Interfaces;

public interface ITenantPropertyPreferenceService
{
    Task<TenantPropertyPreferenceResponse> GetAsync(
        Guid userId,
        CancellationToken cancellationToken = default);

    Task<TenantPropertyPreferenceResponse?> UpdateAsync(
        Guid userId,
        UpdateTenantPropertyPreferenceRequest request,
        CancellationToken cancellationToken = default);

    Task<bool> DeleteAsync(
        Guid userId,
        CancellationToken cancellationToken = default);
}
