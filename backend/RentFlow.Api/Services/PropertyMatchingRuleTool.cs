using RentFlow.Api.DTOs.PropertyMatching;
using RentFlow.Api.Models;
using RentFlow.Api.Services.Interfaces;

namespace RentFlow.Api.Services;

/// <summary>
/// Applies deterministic property matching rules before AI analysis.
/// The AI agent does not calculate authoritative match scores.
/// </summary>
public sealed class PropertyMatchingRuleTool : IPropertyMatchingRuleTool
{
    public Task<List<PropertyMatchCandidate>> ScoreAsync(
        IEnumerable<Property> properties,
        PropertyMatchingRequest preferences,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(properties);
        ArgumentNullException.ThrowIfNull(preferences);

        cancellationToken.ThrowIfCancellationRequested();

        var candidates = new List<PropertyMatchCandidate>();

        foreach (var property in properties)
        {
            cancellationToken.ThrowIfCancellationRequested();

            if (!property.IsAvailable)
            {
                continue;
            }

            var reasons = new List<string>();
            var earnedPoints = 0;
            var possiblePoints = 0;

            if (!string.IsNullOrWhiteSpace(preferences.PreferredCity))
            {
                possiblePoints += 30;

                if (string.Equals(
                    property.City.Trim(),
                    preferences.PreferredCity.Trim(),
                    StringComparison.OrdinalIgnoreCase))
                {
                    earnedPoints += 30;
                    reasons.Add("Preferred city matches.");
                }
            }

            if (preferences.MaximumMonthlyRent.HasValue)
            {
                possiblePoints += 25;

                if (property.MonthlyRent <= preferences.MaximumMonthlyRent.Value)
                {
                    earnedPoints += 25;
                    reasons.Add("Within maximum monthly rent.");
                }
                else
                {
                    reasons.Add("Above preferred maximum monthly rent.");
                }
            }

            if (preferences.MinimumBedrooms.HasValue)
            {
                possiblePoints += 15;

                if (property.Bedrooms >= preferences.MinimumBedrooms.Value)
                {
                    earnedPoints += 15;
                    reasons.Add("Meets bedroom requirement.");
                }
                else
                {
                    reasons.Add("Does not meet bedroom preference.");
                }
            }

            if (preferences.MinimumBathrooms.HasValue)
            {
                possiblePoints += 10;

                if (property.Bathrooms >= preferences.MinimumBathrooms.Value)
                {
                    earnedPoints += 10;
                    reasons.Add("Meets bathroom requirement.");
                }
                else
                {
                    reasons.Add("Does not meet bathroom preference.");
                }
            }

            var preferredAmenities = preferences.PreferredAmenities
                .Where(item => !string.IsNullOrWhiteSpace(item))
                .Select(item => item.Trim())
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .ToList();

            if (preferredAmenities.Count > 0)
            {
                possiblePoints += 20;

                var propertyAmenities = property.Amenities
                    .Select(item => item.Name)
                    .Where(name => !string.IsNullOrWhiteSpace(name))
                    .ToHashSet(StringComparer.OrdinalIgnoreCase);

                var matchedAmenities = preferredAmenities
                    .Count(propertyAmenities.Contains);

                earnedPoints += (int)Math.Round(
                    20m * matchedAmenities / preferredAmenities.Count,
                    MidpointRounding.AwayFromZero);

                reasons.Add(
                    $"Matches {matchedAmenities} of {preferredAmenities.Count} preferred amenities.");
            }

            var score = possiblePoints == 0
                ? 0
                : (int)Math.Round(
                    100m * earnedPoints / possiblePoints,
                    MidpointRounding.AwayFromZero);

            candidates.Add(new PropertyMatchCandidate
            {
                PropertyId = property.Id,
                Title = property.Title,
                City = property.City,
                MonthlyRent = property.MonthlyRent,
                Bedrooms = property.Bedrooms,
                Bathrooms = property.Bathrooms,
                Amenities = property.Amenities
                    .Select(item => item.Name)
                    .Where(name => !string.IsNullOrWhiteSpace(name))
                    .Distinct(StringComparer.OrdinalIgnoreCase)
                    .ToList(),
                MatchScore = Math.Clamp(score, 0, 100),
                MatchReasons = reasons
            });
        }

        return Task.FromResult(
            candidates
                .OrderByDescending(candidate => candidate.MatchScore)
                .ThenBy(candidate => candidate.MonthlyRent)
                .ToList());
    }
}