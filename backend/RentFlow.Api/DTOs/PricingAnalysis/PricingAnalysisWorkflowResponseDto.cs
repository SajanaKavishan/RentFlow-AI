using RentFlow.Api.Models;

namespace RentFlow.Api.DTOs.PricingAnalysis;

public sealed class PricingAnalysisWorkflowResponseDto
{
    public Guid WorkflowId { get; init; }

    public Guid PropertyId { get; init; }

    public PricingAnalysisWorkflowStatus Status { get; init; }

    public string Objective { get; init; } = string.Empty;

    public int CurrentStep { get; init; }

    public string EvidencePolicyVersion { get; init; } = string.Empty;

    public PricingEvidenceSufficiency? EvidenceSufficiency { get; init; }

    public PricingConfidence? Confidence { get; init; }

    public PricingAnalysisResultDto? Result { get; init; }

    public string? ErrorMessage { get; init; }

    public DateTimeOffset CreatedAt { get; init; }

    public DateTimeOffset UpdatedAt { get; init; }

    public DateTimeOffset? StartedAt { get; init; }

    public DateTimeOffset? CompletedAt { get; init; }

    public IReadOnlyCollection<PricingAnalysisWorkflowStepResponseDto> Steps { get; init; } = [];
}

public sealed class PricingAnalysisResultDto
{
    public Guid WorkflowId { get; init; }

    public Guid PropertyId { get; init; }

    public decimal CurrentRent { get; init; }

    public PricingEvidenceSufficiency EvidenceSufficiency { get; init; }

    public PricingConfidence Confidence { get; init; }

    public int UsableEvidenceCount { get; init; }

    public PricingSourceCounts SourceCounts { get; init; } = new();

    public decimal? RecommendedMinRent { get; init; }

    public decimal? RecommendedMaxRent { get; init; }

    public decimal? CentralRecommendedRent { get; init; }

    public string Rationale { get; init; } = string.Empty;

    public IReadOnlyCollection<string> CitedEvidenceRefs { get; init; } = [];

    public IReadOnlyCollection<PricingAnalysisEvidenceSummaryDto> CitedEvidence { get; init; } = [];

    public IReadOnlyCollection<string> Limitations { get; init; } = [];

    public IReadOnlyCollection<string> Warnings { get; init; } = [];

    public bool AdvisoryOnly { get; init; } = true;

    public string EvidencePolicyVersion { get; init; } = "pricing-v1";

    public string? AgentVersion { get; init; }
}

public sealed class PricingAnalysisEvidenceSummaryDto
{
    public string EvidenceRef { get; init; } = string.Empty;

    public PricingEvidenceSourceType SourceType { get; init; }

    public decimal MonthlyRent { get; init; }

    public string City { get; init; } = string.Empty;

    public int Bedrooms { get; init; }

    public int Bathrooms { get; init; }

    public string SourceStatus { get; init; } = string.Empty;

    public DateTimeOffset EvidenceDate { get; init; }

    public PricingEvidenceStrength EvidenceStrength { get; init; }
}

public sealed class PricingAnalysisWorkflowStepResponseDto
{
    public int Order { get; init; }

    public string Name { get; init; } = string.Empty;

    public PricingAnalysisWorkflowStepStatus Status { get; init; }

    public string? OutputSummary { get; init; }

    public string? ValidationSummary { get; init; }

    public string? ErrorMessage { get; init; }

    public DateTimeOffset? StartedAt { get; init; }

    public DateTimeOffset? CompletedAt { get; init; }
}
