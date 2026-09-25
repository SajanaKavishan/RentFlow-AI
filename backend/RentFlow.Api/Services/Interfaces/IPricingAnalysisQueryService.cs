using RentFlow.Api.DTOs.PricingAnalysis;

namespace RentFlow.Api.Services.Interfaces;

public interface IPricingAnalysisQueryService
{
    Task<PricingAnalysisWorkflowResponseDto?> GetByIdAsync(
        Guid workflowId,
        CancellationToken cancellationToken = default);

    Task<IReadOnlyList<PricingAnalysisWorkflowResponseDto>> GetByPropertyAsync(
        Guid propertyId,
        CancellationToken cancellationToken = default);
}
