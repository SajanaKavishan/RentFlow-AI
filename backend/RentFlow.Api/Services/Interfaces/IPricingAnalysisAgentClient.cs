using RentFlow.Api.DTOs.PricingAnalysis;

namespace RentFlow.Api.Services.Interfaces;

public interface IPricingAnalysisAgentClient
{
    Task<PricingAnalysisAgentResponse> AnalyzeAsync(
        PricingAnalysisAgentRequest request,
        CancellationToken cancellationToken = default);
}
