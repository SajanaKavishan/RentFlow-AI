using RentFlow.Api.DTOs.PropertyMatching;

namespace RentFlow.Api.Services.Interfaces;

public interface IPropertyMatchingOrchestrator
{
    Task<PropertyMatchingResponse> MatchAsync(
        PropertyMatchingRequest request,
        CancellationToken cancellationToken = default);
}