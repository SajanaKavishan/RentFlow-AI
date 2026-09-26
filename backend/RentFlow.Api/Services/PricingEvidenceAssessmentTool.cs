using RentFlow.Api.DTOs.PricingAnalysis;
using RentFlow.Api.Services.Interfaces;

namespace RentFlow.Api.Services;

public sealed class PricingEvidenceAssessmentTool : IPricingEvidenceAssessmentTool
{
    private const string InsufficientLimitation =
        "No eligible comparable rental evidence is available; a numerical recommendation is not allowed.";
    private const string LimitedLimitation =
        "Evidence is limited and supports only a cautious advisory analysis.";
    private const string AskingOnlyLimitation =
        "Evidence consists only of listing asking rents, which are not agreed rental transactions.";

    public PricingDeterministicAssessment Assess(
        IReadOnlyCollection<PricingComparableEvidence> evidence)
    {
        ArgumentNullException.ThrowIfNull(evidence);

        var sourceCounts = new PricingSourceCounts
        {
            ListingAskingRent = evidence.Count(item =>
                item.SourceType == PricingEvidenceSourceType.LISTING_ASKING_RENT),
            RentalOffer = evidence.Count(item =>
                item.SourceType == PricingEvidenceSourceType.RENTAL_OFFER),
            LeaseAgreedRent = evidence.Count(item =>
                item.SourceType == PricingEvidenceSourceType.LEASE_AGREED_RENT)
        };
        var count = evidence.Count;
        var askingOnly = count > 0 && sourceCounts.ListingAskingRent == count;

        var sufficiency = count switch
        {
            0 => PricingEvidenceSufficiency.INSUFFICIENT,
            _ when count >= 5 && sourceCounts.LeaseAgreedRent >= 3 =>
                PricingEvidenceSufficiency.STRONG,
            _ when count >= 3 && sourceCounts.LeaseAgreedRent >= 1 =>
                PricingEvidenceSufficiency.MODERATE,
            _ => PricingEvidenceSufficiency.LIMITED
        };

        if (askingOnly)
        {
            sufficiency = PricingEvidenceSufficiency.LIMITED;
        }

        var confidence = sufficiency switch
        {
            PricingEvidenceSufficiency.INSUFFICIENT or PricingEvidenceSufficiency.LIMITED =>
                PricingConfidence.LOW,
            PricingEvidenceSufficiency.MODERATE or PricingEvidenceSufficiency.STRONG =>
                PricingConfidence.MEDIUM,
            _ => PricingConfidence.LOW
        };

        var limitations = new List<string>();
        if (sufficiency == PricingEvidenceSufficiency.INSUFFICIENT)
        {
            limitations.Add(InsufficientLimitation);
        }
        else if (sufficiency == PricingEvidenceSufficiency.LIMITED)
        {
            limitations.Add(askingOnly ? AskingOnlyLimitation : LimitedLimitation);
        }

        return new PricingDeterministicAssessment
        {
            EvidenceSufficiency = sufficiency,
            Confidence = confidence,
            UsableEvidenceCount = count,
            SourceCounts = sourceCounts,
            NumericalRecommendationAllowed = sufficiency != PricingEvidenceSufficiency.INSUFFICIENT,
            Findings = [],
            Limitations = limitations
        };
    }
}
