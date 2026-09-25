namespace RentFlow.Api.DTOs.PricingAnalysis;

/// <summary>
/// Internal-only scope used by deterministic evidence selection. Never serialize to the agent.
/// </summary>
public sealed class PricingEvidenceScope
{
    public Guid SubjectPropertyId { get; init; }

    public Guid SubjectLandlordId { get; init; }

    public PricingPropertyFacts SubjectFacts { get; init; } = new();
}
