using System.Net;
using System.Text;
using Microsoft.Extensions.Options;
using RentFlow.Api.Configuration;
using RentFlow.Api.DTOs.Maintenance;
using RentFlow.Api.Services;
using Xunit;

namespace RentFlow.Api.Tests.Services;

public class MaintenanceCoordinationAgentClientTests
{
    [Fact]
    public async Task AnalyzeAsync_DeserializesAndValidatesSuccessfulResponse()
    {
        var request = CreateRequest();
        var handler = new StubHttpMessageHandler((_, _) => Task.FromResult(JsonResponse(SuccessJson(request.MaintenanceRequestId))));
        var client = CreateClient(handler);

        var result = await client.AnalyzeAsync(request);

        Assert.Equal("plumbing", result.Result.RecommendedCategory);
        Assert.Equal("high", result.Result.RecommendedPriority);
        Assert.Equal("/internal/maintenance-coordination/analyze", handler.LastRequest!.RequestUri!.AbsolutePath);
    }

    [Fact]
    public async Task AnalyzeAsync_ProviderFailureIsMappedSafely()
    {
        var handler = new StubHttpMessageHandler((_, _) => Task.FromResult(
            new HttpResponseMessage(HttpStatusCode.BadGateway)
            {
                Content = new StringContent("provider-secret")
            }));

        var exception = await Assert.ThrowsAsync<MaintenanceCoordinationAgentClientException>(() =>
            CreateClient(handler).AnalyzeAsync(CreateRequest()));

        Assert.Equal(MaintenanceCoordinationAgentClientError.UpstreamFailure, exception.Error);
        Assert.DoesNotContain("provider-secret", exception.Message, StringComparison.Ordinal);
    }

    [Fact]
    public async Task AnalyzeAsync_MalformedResponseIsRejected()
    {
        var handler = new StubHttpMessageHandler((_, _) => Task.FromResult(JsonResponse("{\"maintenanceRequestId\":\"bad\"}")));

        var exception = await Assert.ThrowsAsync<MaintenanceCoordinationAgentClientException>(() =>
            CreateClient(handler).AnalyzeAsync(CreateRequest()));

        Assert.Equal(MaintenanceCoordinationAgentClientError.MalformedResponse, exception.Error);
    }

    private static MaintenanceCoordinationAgentClient CreateClient(StubHttpMessageHandler handler) =>
        new(new HttpClient(handler), Options.Create(new AgentServiceOptions
        {
            BaseUrl = "http://agent.internal:8001",
            TimeoutSeconds = 5
        }));

    private static MaintenanceCoordinationAgentRequest CreateRequest() => new()
    {
        MaintenanceRequestId = Guid.NewGuid(),
        Title = "Leaking tap",
        Description = "Water is leaking.",
        Category = "plumbing",
        Priority = "high",
        CurrentStatus = "open"
    };

    private static string SuccessJson(Guid requestId) => $$"""
        {
          "maintenanceRequestId": "{{requestId}}",
          "result": {
            "recommendedCategory": "plumbing",
            "recommendedPriority": "high",
            "nextAction": "Schedule technician review",
            "reasoning": "A technician should review the leak promptly.",
            "warnings": [],
            "agentVersion": "python-test"
          },
          "executionMetadata": {
            "executedSteps": [
              "plan",
              "classify_assess_issue",
              "assess_urgency",
              "review_maintenance_information",
              "produce_coordination_recommendation",
              "summarize"
            ]
          }
        }
        """;

    private static HttpResponseMessage JsonResponse(string json) => new(HttpStatusCode.OK)
    {
        Content = new StringContent(json, Encoding.UTF8, "application/json")
    };

    private sealed class StubHttpMessageHandler(
        Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>> sendAsync) : HttpMessageHandler
    {
        public HttpRequestMessage? LastRequest { get; private set; }

        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            LastRequest = request;
            return sendAsync(request, cancellationToken);
        }
    }
}