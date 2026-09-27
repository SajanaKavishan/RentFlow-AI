using Microsoft.EntityFrameworkCore;
using RentFlow.Api.Data;
using RentFlow.Api.DTOs.PropertyMatching;
using RentFlow.Api.Services.Interfaces;

namespace RentFlow.Api.Services;

/// <summary>
/// Loads real available properties, applies deterministic scoring,
/// then requests advisory ranking and explanation from the AI agent.
/// </summary>
public sealed class PropertyMatchingOrchestrator(
    ApplicationDbContext dbContext,
    IPropertyMatchingRuleTool propertyMatchingRuleTool,
    IPropertyMatchingAgentClient propertyMatchingAgentClient)
    : IPropertyMatchingOrchestrator
{
    public async Task<PropertyMatchingResponse> MatchAsync(
        PropertyMatchingRequest request,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(request);

        var properties = await dbContext.Properties
            .AsNoTracking()
            .Include(property => property.Amenities)
            .Where(property => property.IsAvailable)
            .ToListAsync(cancellationToken);

        if (properties.Count == 0)
        {
            return new PropertyMatchingResponse
            {
                Matches = [],
                Summary = "No available properties were found."
            };
        }

        var candidates = await propertyMatchingRuleTool.ScoreAsync(
            properties,
            request,
            cancellationToken);

        if (candidates.Count == 0)
        {
            return new PropertyMatchingResponse
            {
                Matches = [],
                Summary = "No matching property candidates were found."
            };
        }

        var agentRequest = new PropertyMatchingAgentRequest
        {
            Preferences = request,
            Candidates = candidates
        };

        var agentResponse =
            await propertyMatchingAgentClient.AnalyzeAsync(
                agentRequest,
                cancellationToken);

        var candidateById = candidates.ToDictionary(
            candidate => candidate.PropertyId);

        var matches = agentResponse.Result.Matches
            .Where(match => candidateById.ContainsKey(match.PropertyId))
            .Select(match =>
            {
                var candidate = candidateById[match.PropertyId];

                return new PropertyMatchCandidate
                {
                    PropertyId = candidate.PropertyId,
                    Title = candidate.Title,
                    City = candidate.City,
                    MonthlyRent = candidate.MonthlyRent,
                    Bedrooms = candidate.Bedrooms,
                    Bathrooms = candidate.Bathrooms,
                    Amenities = candidate.Amenities,
                    MatchScore = candidate.MatchScore,
                    MatchReasons = match.Reasons
                };
            })
            .OrderByDescending(match => match.MatchScore)
            .ThenBy(match => match.MonthlyRent)
            .ToList();

        return new PropertyMatchingResponse
        {
            Matches = matches,
            Summary = agentResponse.Result.Summary
        };
    }
}