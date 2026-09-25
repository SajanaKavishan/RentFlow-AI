using RentFlow.Api.DTOs.PricingAnalysis;

namespace RentFlow.Api.Models;

/// <summary>
/// Represents one durable pricing analysis run for a property.
/// </summary>
public class PricingAnalysisWorkflow
{
    public Guid Id { get; set; } = Guid.NewGuid();

    public Guid PropertyId { get; set; }

    public string Objective { get; set; } = string.Empty;

    public PricingAnalysisWorkflowStatus Status { get; set; } = PricingAnalysisWorkflowStatus.Pending;

    public int CurrentStep { get; set; }

    public string EvidencePolicyVersion { get; set; } = "pricing-v1";

    public PricingEvidenceSufficiency? EvidenceSufficiency { get; set; }

    public PricingConfidence? Confidence { get; set; }

    public string? AgentVersion { get; set; }

    public string? ResultJson { get; set; }

    public string? ErrorMessage { get; set; }

    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;

    public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.UtcNow;

    public DateTimeOffset? StartedAt { get; set; }

    public DateTimeOffset? CompletedAt { get; set; }

    public Property Property { get; set; } = null!;

    public ICollection<PricingAnalysisWorkflowStep> Steps { get; set; } = new List<PricingAnalysisWorkflowStep>();
}
