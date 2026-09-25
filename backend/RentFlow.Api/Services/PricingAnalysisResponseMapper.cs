using System.Text.Json;
using RentFlow.Api.DTOs.PricingAnalysis;

namespace RentFlow.Api.Services;

internal static class PricingAnalysisResponseMapper
{
    internal const string PolicyVersion = "pricing-v1";
    internal const string Objective = "Analyze an evidence-supported monthly rental range.";

    internal static readonly string[] ExpectedSteps =
    [
        "plan",
        "collect_property_facts",
        "collect_rental_evidence",
        "analyse_pricing_evidence",
        "validate_pricing_recommendation",
        "produce_pricing_result"
    ];

    internal const string AnalysisStep = "analyse_pricing_evidence";

    internal const decimal MaximumSupportedRent = 9999999999999999.99m;

    internal static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web)
    {
        UnmappedMemberHandling = System.Text.Json.Serialization.JsonUnmappedMemberHandling.Disallow
    };

    internal static bool IsValidRequest(PricingAnalysisAgentRequest request)
    {
        if (request.WorkflowId == Guid.Empty
            || request.PropertyId == Guid.Empty
            || request.Objective != Objective
            || request.EvidencePolicyVersion != PolicyVersion
            || request.PropertyFacts is null
            || string.IsNullOrWhiteSpace(request.PropertyFacts.City)
            || request.PropertyFacts.City.Length > 100
            || !IsValidRent(request.PropertyFacts.MonthlyRent)
            || request.PropertyFacts.Bedrooms < 0
            || request.PropertyFacts.Bathrooms < 0
            || request.Comparables is null
            || request.Comparables.Count > 100
            || request.DeterministicAssessment is null
            || request.DeterministicAssessment.SourceCounts is null)
        {
            return false;
        }

        var assessment = request.DeterministicAssessment;
        if (!Enum.IsDefined(assessment.EvidenceSufficiency)
            || !Enum.IsDefined(assessment.Confidence)
            || assessment.UsableEvidenceCount != request.Comparables.Count
            || assessment.UsableEvidenceCount < 0
            || assessment.SourceCounts.ListingAskingRent < 0
            || assessment.SourceCounts.RentalOffer < 0
            || assessment.SourceCounts.LeaseAgreedRent < 0
            || (long)assessment.SourceCounts.ListingAskingRent
                + assessment.SourceCounts.RentalOffer
                + assessment.SourceCounts.LeaseAgreedRent != assessment.UsableEvidenceCount
            || (assessment.EvidenceSufficiency == PricingEvidenceSufficiency.INSUFFICIENT)
                != (request.Comparables.Count == 0))
        {
            return false;
        }

        var evidenceRefs = new HashSet<string>(StringComparer.Ordinal);
        foreach (var comparable in request.Comparables)
        {
            if (comparable is null
                || !Enum.IsDefined(comparable.SourceType)
                || !Enum.IsDefined(comparable.EvidenceStrength)
                || string.IsNullOrWhiteSpace(comparable.EvidenceRef)
                || comparable.EvidenceRef.Length > 40
                || !evidenceRefs.Add(comparable.EvidenceRef)
                || !IsValidRent(comparable.MonthlyRent)
                || string.IsNullOrWhiteSpace(comparable.City)
                || comparable.City.Length > 100
                || comparable.Bedrooms < 0
                || comparable.Bathrooms < 0
                || string.IsNullOrWhiteSpace(comparable.SourceStatus)
                || comparable.SourceStatus.Length > 30
                || comparable.RelationshipToSubject != "OTHER_PROPERTY")
            {
                return false;
            }
        }

        return true;
    }

    internal static void ValidateResponse(
        PricingAnalysisAgentRequest request,
        PricingAnalysisAgentResponse? response)
    {
        if (response is null
            || response.WorkflowId != request.WorkflowId
            || response.PropertyId != request.PropertyId
            || string.IsNullOrWhiteSpace(response.AgentVersion)
            || response.AgentVersion.Length > 100
            || response.ModelDraft is null
            || response.ExecutionMetadata is null)
        {
            throw MalformedResponse();
        }

        var draft = response.ModelDraft;
        if (draft.CitedEvidenceRefs is null
            || draft.Rationale is null
            || string.IsNullOrWhiteSpace(draft.Rationale)
            || draft.Rationale.Length > 2000
            || draft.Limitations is null
            || draft.Warnings is null
            || draft.CitedEvidenceRefs.Count > 100
            || draft.Limitations.Count > 50
            || draft.Warnings.Count > 50
            || draft.CitedEvidenceRefs.Any(string.IsNullOrWhiteSpace)
            || draft.Limitations.Any(value => value is null)
            || draft.Warnings.Any(value => value is null))
        {
            throw MalformedResponse();
        }

        var availableRefs = new HashSet<string>(request.Comparables.Select(item => item.EvidenceRef), StringComparer.Ordinal);
        var citedRefs = new HashSet<string>(StringComparer.Ordinal);
        foreach (var evidenceRef in draft.CitedEvidenceRefs)
        {
            if (!availableRefs.Contains(evidenceRef) || !citedRefs.Add(evidenceRef))
            {
                throw MalformedResponse();
            }
        }

        ValidateRecommendations(
            draft,
            request.DeterministicAssessment.EvidenceSufficiency == PricingEvidenceSufficiency.INSUFFICIENT);
        ValidateExecutionMetadata(request, response.ExecutionMetadata);
    }

    internal static PricingAnalysisAgentClientException MalformedResponse() => new(
        PricingAnalysisAgentClientError.MalformedResponse,
        "The pricing analysis agent returned an invalid structured response.");

    private static bool IsValidRent(decimal value) =>
        value > 0
        && value <= MaximumSupportedRent
        && decimal.Round(value, 2, MidpointRounding.ToEven) == value;

    private static void ValidateRecommendations(
        PricingAnalysisAgentModelDraft draft,
        bool isInsufficient)
    {
        var minimum = draft.RecommendedMinRent;
        var maximum = draft.RecommendedMaxRent;
        var central = draft.CentralRecommendedRent;
        if ((minimum is null) != (maximum is null))
        {
            throw MalformedResponse();
        }

        if (minimum is null)
        {
            if (central is not null)
            {
                throw MalformedResponse();
            }
        }
        else if (!IsValidRent(minimum.Value)
            || !IsValidRent(maximum!.Value)
            || minimum.Value > maximum.Value
            || (central is not null
                && (!IsValidRent(central.Value)
                    || central.Value < minimum.Value
                    || central.Value > maximum.Value)))
        {
            throw MalformedResponse();
        }

        if (isInsufficient
            && (minimum is not null || maximum is not null || central is not null || draft.CitedEvidenceRefs!.Count != 0))
        {
            throw MalformedResponse();
        }
    }

    private static void ValidateExecutionMetadata(
        PricingAnalysisAgentRequest request,
        PricingAnalysisAgentExecutionMetadata metadata)
    {
        if (metadata.WorkflowPlanVersion != PolicyVersion
            || metadata.ExpectedSteps is null
            || metadata.ExecutedSteps is null
            || metadata.SkippedSteps is null
            || !metadata.ExpectedSteps.SequenceEqual(ExpectedSteps, StringComparer.Ordinal))
        {
            throw MalformedResponse();
        }

        var isInsufficient = request.DeterministicAssessment.EvidenceSufficiency
            == PricingEvidenceSufficiency.INSUFFICIENT;
        var expectedExecutedSteps = isInsufficient
            ? ExpectedSteps.Where(step => step != AnalysisStep).ToArray()
            : ExpectedSteps;
        var expectedSkippedSteps = isInsufficient ? [AnalysisStep] : Array.Empty<string>();
        if (!metadata.ExecutedSteps.SequenceEqual(expectedExecutedSteps, StringComparer.Ordinal)
            || !metadata.SkippedSteps.SequenceEqual(expectedSkippedSteps, StringComparer.Ordinal))
        {
            throw MalformedResponse();
        }
    }
}
