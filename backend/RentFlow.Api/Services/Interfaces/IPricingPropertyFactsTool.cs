using RentFlow.Api.DTOs.PricingAnalysis;

namespace RentFlow.Api.Services.Interfaces;

public interface IPricingPropertyFactsTool
{
    Task<PricingEvidenceScope?> GetAsync(
        Guid propertyId,
        CancellationToken cancellationToken = default);
}
