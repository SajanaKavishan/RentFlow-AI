using RentFlow.Api.DTOs.PricingAnalysis;

namespace RentFlow.Api.Services.Interfaces;

public interface IPricingAnalysisOrchestrator
{
    Task<PricingAnalysisWorkflowResponseDto> StartAsync(
        Guid propertyId,
        CancellationToken cancellationToken = default);
}
