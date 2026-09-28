using Microsoft.EntityFrameworkCore;
using RentFlow.Api.Data;
using RentFlow.Api.DTOs.PropertyMatching;
using RentFlow.Api.Models;
using RentFlow.Api.Services;
using RentFlow.Api.Services.Interfaces;
using Xunit;

namespace RentFlow.Api.Tests.Services;

public sealed class PropertyMatchingRuleToolTests
{
    [Fact]
    public async Task ScoreAsync_UsesConfiguredDeterministicWeightsAndRealReasons()
    {
        var property = new Property
        {
            Id = Guid.NewGuid(),
            Title = "Lake House",
            City = "Kurunegala",
            MonthlyRent = 120000,
            Bedrooms = 2,
            Bathrooms = 1,
            IsAvailable = true,
            Amenities =
            [
                new PropertyAmenity { Name = "Parking" }
            ]
        };
        var preferences = new PropertyMatchingRequest
        {
            PreferredCity = "Kurunegala",
            MaximumMonthlyRent = 150000,
            MinimumBedrooms = 2,
            MinimumBathrooms = 2,
            PreferredAmenities = ["Parking", "Security"]
        };

        var result = await new PropertyMatchingRuleTool()
            .ScoreAsync([property], preferences);

        var match = Assert.Single(result);
        Assert.Equal(80, match.MatchScore);
        Assert.Contains("Preferred city matches.", match.MatchReasons);
        Assert.Contains("Within maximum monthly rent.", match.MatchReasons);
        Assert.Contains("Meets bedroom requirement.", match.MatchReasons);
        Assert.Contains("Does not meet bathroom preference.", match.MatchReasons);
        Assert.Contains("Matches 1 of 2 preferred amenities.", match.MatchReasons);
    }

    [Fact]
    public async Task ScoreAsync_DoesNotReturnUnavailableProperties()
    {
        var property = new Property
        {
            Id = Guid.NewGuid(),
            Title = "Unavailable",
            City = "Colombo",
            IsAvailable = false
        };

        var result = await new PropertyMatchingRuleTool()
            .ScoreAsync([property], new PropertyMatchingRequest { PreferredCity = "Colombo" });

        Assert.Empty(result);
    }

    [Fact]
    public async Task Orchestrator_KeepsDeterministicReasonsWhenAgentReturnsInventedClaims()
    {
        var options = new DbContextOptionsBuilder<ApplicationDbContext>()
            .UseInMemoryDatabase($"property-matching-{Guid.NewGuid()}")
            .Options;
        await using var context = new ApplicationDbContext(options);
        var property = new Property
        {
            Id = Guid.NewGuid(),
            LandlordId = Guid.NewGuid(),
            Title = "City Home",
            Description = "Real description",
            Address = "1 Main Street",
            City = "Colombo",
            MonthlyRent = 90000,
            Bedrooms = 2,
            Bathrooms = 1,
            IsAvailable = true
        };
        context.Properties.Add(property);
        await context.SaveChangesAsync();
        var orchestrator = new PropertyMatchingOrchestrator(
            context,
            new PropertyMatchingRuleTool(),
            new InventingAgentClient());

        var response = await orchestrator.MatchAsync(new PropertyMatchingRequest
        {
            PreferredCity = "Colombo"
        });

        var match = Assert.Single(response.Matches);
        Assert.Equal(100, match.MatchScore);
        Assert.Equal(["Preferred city matches."], match.MatchReasons);
        Assert.DoesNotContain("Includes a private swimming pool.", match.MatchReasons);
    }

    private sealed class InventingAgentClient : IPropertyMatchingAgentClient
    {
        public Task<PropertyMatchingAgentResponse> AnalyzeAsync(
            PropertyMatchingAgentRequest request,
            CancellationToken cancellationToken = default)
        {
            var candidate = Assert.Single(request.Candidates);
            return Task.FromResult(new PropertyMatchingAgentResponse
            {
                Result = new PropertyMatchingAgentResult
                {
                    Summary = "Advisory summary.",
                    AgentVersion = "test",
                    Matches =
                    [
                        new PropertyMatchingAgentMatch
                        {
                            PropertyId = candidate.PropertyId,
                            MatchScore = candidate.MatchScore,
                            Reasons = ["Includes a private swimming pool."]
                        }
                    ]
                },
                ExecutionMetadata = new PropertyMatchingExecutionMetadata
                {
                    ExecutedSteps = ["plan", "analyze_matches", "summarize"]
                }
            });
        }
    }
}
