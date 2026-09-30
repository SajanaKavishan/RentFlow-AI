using RentFlow.Api.DTOs;
using RentFlow.Api.Models;

namespace RentFlow.Api.Services;

/// <summary>
/// Shared normalization for listings, filters, and tenant matching.
/// Unknown amenity names are deliberately preserved as custom values.
/// </summary>
public static class PropertyListingCatalog
{
    private static readonly IReadOnlyDictionary<string, string> AmenityLabels =
        new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            ["wifi"] = "Wi-Fi",
            ["parking"] = "Parking",
            ["air-conditioning"] = "Air conditioning",
            ["washer-dryer"] = "Washer / dryer",
            ["gym"] = "Gym",
            ["swimming-pool"] = "Swimming pool",
            ["balcony"] = "Balcony",
            ["elevator"] = "Elevator",
            ["furnished"] = "Furnished",
            ["garden"] = "Garden",
            ["security"] = "Security",
            ["rooftop"] = "Rooftop"
        };

    private static readonly IReadOnlyDictionary<string, string> AmenityAliases =
        new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            ["wifi"] = "wifi", ["wi fi"] = "wifi", ["wireless internet"] = "wifi",
            ["parking"] = "parking", ["car parking"] = "parking",
            ["air conditioning"] = "air-conditioning", ["air conditioner"] = "air-conditioning",
            ["a c"] = "air-conditioning", ["ac"] = "air-conditioning",
            ["washer dryer"] = "washer-dryer", ["washer and dryer"] = "washer-dryer",
            ["laundry"] = "washer-dryer",
            ["gym"] = "gym", ["fitness centre"] = "gym", ["fitness center"] = "gym",
            ["swimming pool"] = "swimming-pool", ["pool"] = "swimming-pool",
            ["balcony"] = "balcony",
            ["elevator"] = "elevator", ["lift"] = "elevator",
            ["furnished"] = "furnished",
            ["garden"] = "garden",
            ["security"] = "security", ["security service"] = "security",
            ["rooftop"] = "rooftop", ["roof terrace"] = "rooftop"
        };

    public static readonly IReadOnlySet<string> UtilityKeys =
        new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "water", "electricity", "internet", "gas", "waste-collection"
        };

    private static readonly IReadOnlyDictionary<string, string> UtilityAliases =
        new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            ["water"] = "water",
            ["electricity"] = "electricity", ["electric"] = "electricity",
            ["internet"] = "internet",
            ["gas"] = "gas",
            ["waste collection"] = "waste-collection", ["garbage collection"] = "waste-collection"
        };

    public static bool IsCanonicalAmenity(string? value) =>
        value is not null && AmenityLabels.ContainsKey(value.Trim());

    public static string? CanonicalizeAmenity(string? value)
    {
        var normalized = NormalizeLookup(value);
        if (normalized is null)
        {
            return null;
        }

        if (AmenityLabels.ContainsKey(normalized))
        {
            return normalized;
        }

        return AmenityAliases.TryGetValue(normalized, out var key) ? key : null;
    }

    public static string CanonicalAmenityLabel(string key) => AmenityLabels[key];

    public static string NormalizeForMatching(string value) =>
        CanonicalizeAmenity(value) ?? NormalizeLookup(value) ?? string.Empty;

    public static string[]? NormalizeUtilities(IEnumerable<string>? values)
    {
        if (values is null)
        {
            return null;
        }

        return values
            .Select(CanonicalizeUtility)
            .Where(value => value is not null)
            .Cast<string>()
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();
    }

    public static bool UtilitiesAreValid(IEnumerable<string>? values) =>
        values is null || values.All(value =>
            CanonicalizeUtility(value) is not null);

    private static string? CanonicalizeUtility(string? value) =>
        NormalizeLookup(value) is string normalized
            && UtilityAliases.TryGetValue(normalized, out var canonical)
                ? canonical
                : null;

    public static IReadOnlyList<PropertyAmenity> NormalizeAmenities(
        Guid propertyId,
        IEnumerable<string>? legacyNames,
        IEnumerable<PropertyAmenityInputDto>? inputs)
    {
        var candidates = new List<(string? CanonicalKey, string Name)>();

        foreach (var rawName in legacyNames ?? [])
        {
            AddCandidate(candidates, rawName, null);
        }

        foreach (var input in inputs ?? [])
        {
            if (!string.IsNullOrWhiteSpace(input.CanonicalKey))
            {
                AddCandidate(candidates, input.CanonicalKey, input.CanonicalKey);
            }
            else
            {
                AddCandidate(candidates, input.CustomName, null);
            }
        }

        var canonicalSeen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var customSeen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var result = new List<PropertyAmenity>();
        foreach (var candidate in candidates)
        {
            if (candidate.CanonicalKey is not null)
            {
                if (!canonicalSeen.Add(candidate.CanonicalKey)) continue;
            }
            else if (!customSeen.Add(candidate.Name))
            {
                continue;
            }

            result.Add(new PropertyAmenity
            {
                Id = Guid.NewGuid(),
                PropertyId = propertyId,
                CanonicalKey = candidate.CanonicalKey,
                Name = candidate.Name
            });
        }

        return result;
    }

    private static void AddCandidate(
        ICollection<(string? CanonicalKey, string Name)> candidates,
        string? rawName,
        string? explicitCanonicalKey)
    {
        if (string.IsNullOrWhiteSpace(rawName)) return;

        var trimmed = rawName.Trim();
        var canonical = CanonicalizeAmenity(explicitCanonicalKey ?? trimmed);
        if (explicitCanonicalKey is not null && canonical is null) return;

        candidates.Add(canonical is null
            ? (null, trimmed)
            : (canonical, CanonicalAmenityLabel(canonical)));
    }

    private static string? NormalizeLookup(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return null;

        return string.Join(' ', value.Trim().ToLowerInvariant()
            .Replace("&", " and ", StringComparison.Ordinal)
            .Split(['-', '_', '/', ' ', '.'], StringSplitOptions.RemoveEmptyEntries));
    }
}
