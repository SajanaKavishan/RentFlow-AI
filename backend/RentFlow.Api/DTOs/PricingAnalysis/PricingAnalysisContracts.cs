using System.Text.Json.Serialization;

namespace RentFlow.Api.DTOs.PricingAnalysis;

public sealed class PricingPropertyFacts
{
    public Guid PropertyId { get; init; }

    public string City { get; init; } = string.Empty;

    public decimal MonthlyRent { get; init; }

    public int Bedrooms { get; init; }

    public int Bathrooms { get; init; }

    public bool IsAvailable { get; init; }

    public DateTimeOffset SnapshotAt { get; init; }
}

[JsonConverter(typeof(JsonStringEnumConverter<PricingEvidenceSourceType>))]
public enum PricingEvidenceSourceType
{
    LISTING_ASKING_RENT,
    RENTAL_OFFER,
    LEASE_AGREED_RENT
}

[JsonConverter(typeof(JsonStringEnumConverter<PricingEvidenceStrength>))]
public enum PricingEvidenceStrength
{
    LOW,
    MEDIUM,
    HIGH
}

[JsonConverter(typeof(JsonStringEnumConverter<PricingEvidenceSufficiency>))]
public enum PricingEvidenceSufficiency
{
    INSUFFICIENT,
    LIMITED,
    MODERATE,
    STRONG
}

[JsonConverter(typeof(JsonStringEnumConverter<PricingConfidence>))]
public enum PricingConfidence
{
    LOW,
    MEDIUM,
    HIGH
}

public sealed class PricingComparableEvidence
{
    public string EvidenceRef { get; init; } = string.Empty;

    [JsonConverter(typeof(JsonStringEnumConverter<PricingEvidenceSourceType>))]
    public PricingEvidenceSourceType SourceType { get; init; }

    public decimal MonthlyRent { get; init; }

    public string City { get; init; } = string.Empty;

    public int Bedrooms { get; init; }

    public int Bathrooms { get; init; }

    public string SourceStatus { get; init; } = string.Empty;

    public DateTimeOffset EvidenceDate { get; init; }

    [JsonConverter(typeof(JsonStringEnumConverter<PricingEvidenceStrength>))]
    public PricingEvidenceStrength EvidenceStrength { get; init; }
}

public sealed class PricingSourceCounts
{
    public int ListingAskingRent { get; init; }

    public int RentalOffer { get; init; }

    public int LeaseAgreedRent { get; init; }
}

public sealed class PricingDeterministicAssessment
{
    [JsonConverter(typeof(JsonStringEnumConverter<PricingEvidenceSufficiency>))]
    public PricingEvidenceSufficiency EvidenceSufficiency { get; init; }

    [JsonConverter(typeof(JsonStringEnumConverter<PricingConfidence>))]
    public PricingConfidence Confidence { get; init; }

    public int UsableEvidenceCount { get; init; }

    public PricingSourceCounts SourceCounts { get; init; } = new();

    public bool NumericalRecommendationAllowed { get; init; }

    public IReadOnlyCollection<string> Findings { get; init; } = Array.Empty<string>();

    public IReadOnlyCollection<string> Limitations { get; init; } = Array.Empty<string>();
}
