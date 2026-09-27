using RentFlow.Api.DTOs.PricingAnalysis;

namespace RentFlow.Api.Services.Interfaces;

public interface IPricingEvidenceAssessmentTool
{
    PricingDeterministicAssessment Assess(
        IReadOnlyCollection<PricingComparableEvidence> evidence);
}
