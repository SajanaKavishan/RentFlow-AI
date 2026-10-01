namespace RentFlow.Api.DTOs.PropertyMatching;

public sealed class TenantPropertyFavoritesResponse
{
    public List<Guid> PropertyIds { get; init; } = [];
}
