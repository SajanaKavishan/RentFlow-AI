using Microsoft.EntityFrameworkCore;
using RentFlow.Api.Data;
using RentFlow.Api.DTOs.PropertyMatching;
using RentFlow.Api.Services.Interfaces;

namespace RentFlow.Api.Services;

/// <summary>
/// Loads real available properties, applies deterministic scoring,
/// then optionally requests an advisory explanation from the AI agent.
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

        var matches = candidates
            .OrderByDescending(match => match.MatchScore)
            .ThenBy(match => match.MonthlyRent)
            .ToList();
        var fallbackSummary =
            "Properties ranked using your saved match preferences.";
        PropertyMatchingAgentResponse? agentResponse = null;

        try
        {
            agentResponse = await propertyMatchingAgentClient.AnalyzeAsync(
                new PropertyMatchingAgentRequest
                {
                    Preferences = request,
                    Candidates = matches
                },
                cancellationToken);
        }
        catch (OperationCanceledException)
            when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception)
            when (!cancellationToken.IsCancellationRequested)
        {
            // Explanation enrichment is advisory. Deterministic scores,
            // reasons, and ordering remain useful without the agent.
        }

        var explanationAvailable =
            !string.IsNullOrWhiteSpace(agentResponse?.Result?.Summary);

        return new PropertyMatchingResponse
        {
            Matches = matches,
            Summary = explanationAvailable
                ? agentResponse!.Result.Summary
                : fallbackSummary,
            ExplanationAvailable = explanationAvailable
        };
    }
}
