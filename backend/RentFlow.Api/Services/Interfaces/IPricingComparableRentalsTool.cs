using RentFlow.Api.DTOs.PricingAnalysis;

namespace RentFlow.Api.Services.Interfaces;

public interface IPricingComparableRentalsTool
{
    Task<IReadOnlyCollection<PricingComparableEvidence>> GetAsync(
        PricingEvidenceScope subject,
        CancellationToken cancellationToken = default);
}
