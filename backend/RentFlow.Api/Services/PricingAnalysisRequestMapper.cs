using RentFlow.Api.DTOs.PricingAnalysis;

namespace RentFlow.Api.Services;

public static class PricingAnalysisRequestMapper
{
    public static PricingAnalysisAgentRequest Create(
        Guid workflowId,
        Guid propertyId,
        string objective,
        PricingPropertyFacts propertyFacts,
        IReadOnlyCollection<PricingComparableEvidence> comparables,
        PricingDeterministicAssessment assessment,
        string evidencePolicyVersion)
    {
        ArgumentNullException.ThrowIfNull(propertyFacts);
        ArgumentNullException.ThrowIfNull(comparables);
        ArgumentNullException.ThrowIfNull(assessment);
        ArgumentNullException.ThrowIfNull(assessment.SourceCounts);
        if (propertyFacts.PropertyId != propertyId)
        {
            throw new ArgumentException("Property facts must belong to the requested property.", nameof(propertyFacts));
        }

        return new PricingAnalysisAgentRequest
        {
            WorkflowId = workflowId,
            PropertyId = propertyId,
            Objective = objective,
            PropertyFacts = new PricingAnalysisAgentPropertyFacts
            {
                City = propertyFacts.City,
                MonthlyRent = propertyFacts.MonthlyRent,
                Bedrooms = propertyFacts.Bedrooms,
                Bathrooms = propertyFacts.Bathrooms,
                IsAvailable = propertyFacts.IsAvailable,
                SnapshotAt = propertyFacts.SnapshotAt
            },
            Comparables = comparables.Select(item => new PricingAnalysisAgentComparable
            {
                EvidenceRef = item.EvidenceRef,
                SourceType = item.SourceType,
                MonthlyRent = item.MonthlyRent,
                City = item.City,
                Bedrooms = item.Bedrooms,
                Bathrooms = item.Bathrooms,
                SourceStatus = item.SourceStatus,
                RelationshipToSubject = "OTHER_PROPERTY",
                EvidenceDate = item.EvidenceDate,
                EvidenceStrength = item.EvidenceStrength
            }).ToArray(),
            DeterministicAssessment = new PricingAnalysisAgentAssessment
            {
                EvidenceSufficiency = assessment.EvidenceSufficiency,
                Confidence = assessment.Confidence,
                UsableEvidenceCount = assessment.UsableEvidenceCount,
                SourceCounts = new PricingAnalysisAgentSourceCounts
                {
                    ListingAskingRent = assessment.SourceCounts.ListingAskingRent,
                    RentalOffer = assessment.SourceCounts.RentalOffer,
                    LeaseAgreedRent = assessment.SourceCounts.LeaseAgreedRent
                }
            },
            EvidencePolicyVersion = evidencePolicyVersion
        };
    }
}
