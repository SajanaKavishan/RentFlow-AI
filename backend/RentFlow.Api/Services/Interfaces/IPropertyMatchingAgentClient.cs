using RentFlow.Api.DTOs.PropertyMatching;

namespace RentFlow.Api.Services.Interfaces;

public interface IPropertyMatchingAgentClient
{
    Task<PropertyMatchingAgentResponse> AnalyzeAsync(
        PropertyMatchingAgentRequest request,
        CancellationToken cancellationToken = default);
}