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
        Assert.True(response.ExplanationAvailable);
        Assert.Equal("Advisory summary.", response.Summary);
    }

    [Fact]
    public async Task Orchestrator_ReturnsIdenticalDeterministicMatchesWhenAgentThrows()
    {
        await using var context = CreateContext();
        await AddAvailableProperties(context);
        var preferences = new PropertyMatchingRequest
        {
            PreferredCity = "Colombo",
            MaximumMonthlyRent = 100000,
            MinimumBedrooms = 2
        };
        var successful = await new PropertyMatchingOrchestrator(
            context,
            new PropertyMatchingRuleTool(),
            new ReversingAgentClient()).MatchAsync(preferences);
        var unavailable = await new PropertyMatchingOrchestrator(
            context,
            new PropertyMatchingRuleTool(),
            new ThrowingAgentClient(new InvalidOperationException(
                "provider-secret: model deployment unavailable")))
            .MatchAsync(preferences);

        Assert.True(successful.ExplanationAvailable);
        Assert.False(unavailable.ExplanationAvailable);
        Assert.Equal(
            successful.Matches.Select(match => match.PropertyId),
            unavailable.Matches.Select(match => match.PropertyId));
        Assert.Equal(
            successful.Matches.Select(match => match.MatchScore),
            unavailable.Matches.Select(match => match.MatchScore));
        Assert.Equal(
            successful.Matches.Select(match => string.Join('|', match.MatchReasons)),
            unavailable.Matches.Select(match => string.Join('|', match.MatchReasons)));
        Assert.DoesNotContain("provider-secret", unavailable.Summary);
        Assert.Equal(
            "Properties ranked using your saved match preferences.",
            unavailable.Summary);
    }

    [Theory]
    [InlineData("timeout")]
    [InlineData("unavailable")]
    public async Task Orchestrator_ReturnsDeterministicMatchesWhenAgentCannotRespond(
        string failure)
    {
        await using var context = CreateContext();
        await AddAvailableProperties(context);
        Exception exception = failure == "timeout"
            ? new TaskCanceledException("agent request timed out")
            : new HttpRequestException("agent host unavailable");
        var response = await new PropertyMatchingOrchestrator(
            context,
            new PropertyMatchingRuleTool(),
            new ThrowingAgentClient(exception)).MatchAsync(
                new PropertyMatchingRequest { PreferredCity = "Colombo" });

        Assert.Equal(2, response.Matches.Count);
        Assert.False(response.ExplanationAvailable);
        Assert.Contains(
            response.Matches,
            match => match.MatchReasons.Contains("Preferred city matches."));
    }

    [Fact]
    public async Task Orchestrator_DoesNotHideDeterministicMatchingFailure()
    {
        await using var context = CreateContext();
        await AddAvailableProperties(context);
        var orchestrator = new PropertyMatchingOrchestrator(
            context,
            new ThrowingRuleTool(),
            new ReversingAgentClient());

        var exception = await Assert.ThrowsAsync<InvalidOperationException>(
            () => orchestrator.MatchAsync(new PropertyMatchingRequest
            {
                PreferredCity = "Colombo"
            }));

        Assert.Equal("deterministic matching failed", exception.Message);
    }

    [Fact]
    public async Task Orchestrator_InvalidAgentOutput_OmitsExplanationOnly()
    {
        await using var context = CreateContext();
        await AddAvailableProperties(context);
        var response = await new PropertyMatchingOrchestrator(
            context,
            new PropertyMatchingRuleTool(),
            new InvalidAgentClient()).MatchAsync(
                new PropertyMatchingRequest { PreferredCity = "Colombo" });

        Assert.Equal(2, response.Matches.Count);
        Assert.False(response.ExplanationAvailable);
        Assert.Equal(
            "Properties ranked using your saved match preferences.",
            response.Summary);
    }

    private static ApplicationDbContext CreateContext()
    {
        var options = new DbContextOptionsBuilder<ApplicationDbContext>()
            .UseInMemoryDatabase($"property-matching-{Guid.NewGuid()}")
            .Options;
        return new ApplicationDbContext(options);
    }

    private static async Task AddAvailableProperties(ApplicationDbContext context)
    {
        context.Properties.AddRange(
            new Property
            {
                Id = Guid.NewGuid(),
                LandlordId = Guid.NewGuid(),
                Title = "Colombo Apartment",
                Description = "Real description",
                Address = "1 Main Street",
                City = "Colombo",
                MonthlyRent = 90000,
                Bedrooms = 2,
                Bathrooms = 1,
                IsAvailable = true
            },
            new Property
            {
                Id = Guid.NewGuid(),
                LandlordId = Guid.NewGuid(),
                Title = "Galle Studio",
                Description = "Real description",
                Address = "2 Beach Road",
                City = "Galle",
                MonthlyRent = 70000,
                Bedrooms = 1,
                Bathrooms = 1,
                IsAvailable = true
            });
        await context.SaveChangesAsync();
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

    private sealed class ReversingAgentClient : IPropertyMatchingAgentClient
    {
        public Task<PropertyMatchingAgentResponse> AnalyzeAsync(
            PropertyMatchingAgentRequest request,
            CancellationToken cancellationToken = default)
        {
            return Task.FromResult(new PropertyMatchingAgentResponse
            {
                Result = new PropertyMatchingAgentResult
                {
                    Summary = "Advisory summary.",
                    AgentVersion = "test",
                    Matches = request.Candidates
                        .AsEnumerable()
                        .Reverse()
                        .Select(candidate => new PropertyMatchingAgentMatch
                        {
                            PropertyId = candidate.PropertyId,
                            MatchScore = candidate.MatchScore,
                            Reasons = ["Advisory only."]
                        })
                        .ToList()
                },
                ExecutionMetadata = new PropertyMatchingExecutionMetadata
                {
                    ExecutedSteps = ["plan", "analyze_matches", "summarize"]
                }
            });
        }
    }

    private sealed class ThrowingAgentClient(Exception exception)
        : IPropertyMatchingAgentClient
    {
        public Task<PropertyMatchingAgentResponse> AnalyzeAsync(
            PropertyMatchingAgentRequest request,
            CancellationToken cancellationToken = default)
        {
            return Task.FromException<PropertyMatchingAgentResponse>(exception);
        }
    }

    private sealed class InvalidAgentClient : IPropertyMatchingAgentClient
    {
        public Task<PropertyMatchingAgentResponse> AnalyzeAsync(
            PropertyMatchingAgentRequest request,
            CancellationToken cancellationToken = default)
        {
            return Task.FromResult(new PropertyMatchingAgentResponse());
        }
    }

    private sealed class ThrowingRuleTool : IPropertyMatchingRuleTool
    {
        public Task<List<PropertyMatchCandidate>> ScoreAsync(
            IEnumerable<Property> properties,
            PropertyMatchingRequest preferences,
            CancellationToken cancellationToken = default)
        {
            return Task.FromException<List<PropertyMatchCandidate>>(
                new InvalidOperationException("deterministic matching failed"));
        }
    }
}
