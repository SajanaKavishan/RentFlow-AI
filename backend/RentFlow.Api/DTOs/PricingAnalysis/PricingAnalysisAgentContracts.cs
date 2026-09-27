using System.Text.Json.Serialization;

namespace RentFlow.Api.DTOs.PricingAnalysis;

public sealed class PricingAnalysisAgentRequest
{
    public Guid WorkflowId { get; init; }

    public Guid PropertyId { get; init; }

    public string Objective { get; init; } = string.Empty;

    public PricingAnalysisAgentPropertyFacts PropertyFacts { get; init; } = new();

    public IReadOnlyCollection<PricingAnalysisAgentComparable> Comparables { get; init; } = [];

    public PricingAnalysisAgentAssessment DeterministicAssessment { get; init; } = new();

    public string EvidencePolicyVersion { get; init; } = string.Empty;
}

public sealed class PricingAnalysisAgentPropertyFacts
{
    public string City { get; init; } = string.Empty;

    public decimal MonthlyRent { get; init; }

    public int Bedrooms { get; init; }

    public int Bathrooms { get; init; }

    public bool IsAvailable { get; init; }

    public DateTimeOffset SnapshotAt { get; init; }
}

public sealed class PricingAnalysisAgentComparable
{
    public string EvidenceRef { get; init; } = string.Empty;

    public PricingEvidenceSourceType SourceType { get; init; }

    public decimal MonthlyRent { get; init; }

    public string City { get; init; } = string.Empty;

    public int Bedrooms { get; init; }

    public int Bathrooms { get; init; }

    public string SourceStatus { get; init; } = string.Empty;

    public string RelationshipToSubject { get; init; } = string.Empty;

    public DateTimeOffset EvidenceDate { get; init; }

    public PricingEvidenceStrength EvidenceStrength { get; init; }
}

public sealed class PricingAnalysisAgentAssessment
{
    public PricingEvidenceSufficiency EvidenceSufficiency { get; init; }

    public PricingConfidence Confidence { get; init; }

    public int UsableEvidenceCount { get; init; }

    public PricingAnalysisAgentSourceCounts SourceCounts { get; init; } = new();
}

public sealed class PricingAnalysisAgentSourceCounts
{
    public int ListingAskingRent { get; init; }

    public int RentalOffer { get; init; }

    public int LeaseAgreedRent { get; init; }
}

[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed class PricingAnalysisAgentResponse
{
    public Guid WorkflowId { get; init; }

    public Guid PropertyId { get; init; }

    public PricingAnalysisAgentModelDraft? ModelDraft { get; init; }

    public PricingAnalysisAgentExecutionMetadata? ExecutionMetadata { get; init; }

    public string? AgentVersion { get; init; }
}

[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed class PricingAnalysisAgentModelDraft
{
    public decimal? RecommendedMinRent { get; init; }

    public decimal? RecommendedMaxRent { get; init; }

    public decimal? CentralRecommendedRent { get; init; }

    public IReadOnlyCollection<string>? CitedEvidenceRefs { get; init; }

    public string? Rationale { get; init; }

    public IReadOnlyCollection<string>? Limitations { get; init; }

    public IReadOnlyCollection<string>? Warnings { get; init; }
}

[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed class PricingAnalysisAgentExecutionMetadata
{
    public string? WorkflowPlanVersion { get; init; }

    public IReadOnlyCollection<string>? ExpectedSteps { get; init; }

    public IReadOnlyCollection<string>? ExecutedSteps { get; init; }

    public IReadOnlyCollection<string>? SkippedSteps { get; init; }
}
