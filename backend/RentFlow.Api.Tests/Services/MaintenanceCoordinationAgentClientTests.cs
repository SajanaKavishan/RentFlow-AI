using System.Net;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.Extensions.Options;
using RentFlow.Api.Configuration;
using RentFlow.Api.DTOs.Maintenance;
using RentFlow.Api.Models;
using RentFlow.Api.Services;
using Xunit;

namespace RentFlow.Api.Tests.Services;

public class MaintenanceCoordinationAgentClientTests
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    [Fact]
    public async Task AnalyzeAsync_ValidatesResponseAndSendsOnlyServiceCredential()
    {
        var request = CreateRequest();
        var handler = new StubHttpMessageHandler((message, _) =>
        {
            Assert.Equal("test-service-key", Assert.Single(message.Headers.GetValues("X-RentFlow-Service-Key")));
            Assert.Null(message.Headers.Authorization);
            Assert.Equal("4", Assert.Single(message.Headers.GetValues("X-RentFlow-Analysis-Budget-Seconds")));
            Assert.Equal("/internal/maintenance-coordination/analyze", message.RequestUri!.AbsolutePath);
            return Task.FromResult(JsonResponse(SuccessJson(request)));
        });
        var result = await CreateClient(handler).AnalyzeAsync(request);
        Assert.Equal("Plumbing", result.Result.SuggestedCategory);
        Assert.True(result.Result.RequiresHumanReview);
    }

    public static IEnumerable<object[]> BadResults()
    {
        yield return ["suggestedCategory", JsonValue.Create("plumbing")!];
        yield return ["suggestedCategory", JsonValue.Create("Invented")!];
        yield return ["suggestedPriority", JsonValue.Create("urgent")!];
        yield return ["categoryConfidence", JsonValue.Create("Certain")!];
        yield return ["priorityConfidence", JsonValue.Create("Certain")!];
        yield return ["recommendedTechnicianCategory", JsonValue.Create("Electrician")!];
        yield return ["nextAction", JsonValue.Create("complete-work")!];
        yield return ["requiresHumanReview", JsonValue.Create(false)!];
        yield return ["unexpected", JsonValue.Create(true)!];
        yield return ["rationale", JsonValue.Create(new string('x', 3001))!];
        yield return ["validationFlags", JsonNode.Parse("[{\"code\":\"Invented\",\"message\":\"Bad\"}]")!];
        yield return ["validationFlags", JsonNode.Parse("[{\"code\":\"PhotoUnreadable\",\"message\":\" \"}]")!];
    }

    [Theory]
    [MemberData(nameof(BadResults))]
    public async Task AnalyzeAsync_RejectsUnsafeOrUnknownResult(string field, JsonNode value)
    {
        var request = CreateRequest();
        var json = JsonNode.Parse(SuccessJson(request))!;
        json["result"]![field] = value.DeepClone();
        var exception = await Assert.ThrowsAsync<MaintenanceCoordinationAgentClientException>(() =>
            CreateClient(new((_, _) => Task.FromResult(JsonResponse(json.ToJsonString())))).AnalyzeAsync(request));
        Assert.Equal(MaintenanceCoordinationAgentClientError.MalformedResponse, exception.Error);
    }

    [Fact]
    public async Task AnalyzeAsync_RejectsMissingRequiredNullableField()
    {
        var request = CreateRequest();
        var json = JsonNode.Parse(SuccessJson(request))!;
        json["result"]!.AsObject().Remove("suggestedCategory");
        await Assert.ThrowsAsync<MaintenanceCoordinationAgentClientException>(() =>
            CreateClient(new((_, _) => Task.FromResult(JsonResponse(json.ToJsonString())))).AnalyzeAsync(request));
    }

    [Theory]
    [InlineData(401)]
    [InlineData(503)]
    [InlineData(502)]
    public async Task AnalyzeAsync_UpstreamFailureIsSafe(int status)
    {
        var handler = new StubHttpMessageHandler((_, _) => Task.FromResult(new HttpResponseMessage((HttpStatusCode)status)
            { Content = new StringContent("provider-secret") }));
        var error = await Assert.ThrowsAsync<MaintenanceCoordinationAgentClientException>(() => CreateClient(handler).AnalyzeAsync(CreateRequest()));
        Assert.Equal(MaintenanceCoordinationAgentClientError.UpstreamFailure, error.Error);
        Assert.DoesNotContain("provider-secret", error.Message);
    }

    [Fact]
    public async Task AnalyzeAsync_TimesOutSafely()
    {
        var handler = new StubHttpMessageHandler(async (_, token) =>
        {
            await Task.Delay(Timeout.Infinite, token);
            return JsonResponse("{}");
        });
        var client = new MaintenanceCoordinationAgentClient(new HttpClient(handler), Options.Create(new AgentServiceOptions
            { BaseUrl = "http://agent.test", TimeoutSeconds = 1, ServiceApiKey = "test-service-key" }));
        var error = await Assert.ThrowsAsync<MaintenanceCoordinationAgentClientException>(() => client.AnalyzeAsync(CreateRequest()));
        Assert.Equal(MaintenanceCoordinationAgentClientError.Timeout, error.Error);
    }

    [Fact]
    public async Task AnalyzeAsync_RequiresConfiguredCredential()
    {
        var handler = new StubHttpMessageHandler((_, _) => throw new InvalidOperationException("Must not send"));
        var client = new MaintenanceCoordinationAgentClient(new HttpClient(handler), Options.Create(new AgentServiceOptions()));
        var error = await Assert.ThrowsAsync<MaintenanceCoordinationAgentClientException>(() => client.AnalyzeAsync(CreateRequest()));
        Assert.Equal(MaintenanceCoordinationAgentClientError.Configuration, error.Error);
    }

    [Fact]
    public async Task AnalyzeAsync_AcceptsExplicitAbstention()
    {
        var request = CreateRequest();
        var json = JsonNode.Parse(SuccessJson(request))!;
        var result = json["result"]!;
        result["suggestedCategory"] = null; result["categoryConfidence"] = "Unknown";
        result["suggestedPriority"] = null; result["priorityConfidence"] = "Low";
        result["recommendedTechnicianCategory"] = null; result["nextAction"] = null;
        var response = await CreateClient(new((_, _) => Task.FromResult(JsonResponse(json.ToJsonString())))).AnalyzeAsync(request);
        Assert.Null(response.Result.SuggestedCategory);
    }

    [Theory]
    [InlineData(MaintenanceRequestStatus.Submitted, "triage")]
    [InlineData(MaintenanceRequestStatus.Triaged, "assign-technician")]
    [InlineData(MaintenanceRequestStatus.Assigned, "estimate-pending")]
    [InlineData(MaintenanceRequestStatus.EstimatePending, "submit-estimate")]
    [InlineData(MaintenanceRequestStatus.EstimateSubmitted, "submit-for-review")]
    [InlineData(MaintenanceRequestStatus.AwaitingLandlordApproval, "review-estimate")]
    [InlineData(MaintenanceRequestStatus.Approved, "start-work")]
    [InlineData(MaintenanceRequestStatus.InProgress, "complete-work")]
    [InlineData(MaintenanceRequestStatus.Completed, null)]
    [InlineData(MaintenanceRequestStatus.Rejected, null)]
    [InlineData(MaintenanceRequestStatus.Cancelled, null)]
    public async Task AnalyzeAsync_UsesActualState(MaintenanceRequestStatus status, string? action)
    {
        var request = CreateRequest(status);
        var response = await CreateClient(new((_, _) => Task.FromResult(JsonResponse(SuccessJson(request))))).AnalyzeAsync(request);
        Assert.Equal(action, response.Result.NextAction);
        var json = JsonNode.Parse(SuccessJson(request))!;
        json["result"]!["nextAction"] = action == "complete-work" ? "triage" : "complete-work";
        await Assert.ThrowsAsync<MaintenanceCoordinationAgentClientException>(() =>
            CreateClient(new((_, _) => Task.FromResult(JsonResponse(json.ToJsonString())))).AnalyzeAsync(request));
    }

    private static MaintenanceCoordinationAgentClient CreateClient(StubHttpMessageHandler handler) =>
        new(new HttpClient(handler), Options.Create(new AgentServiceOptions
        { BaseUrl = "http://agent.internal:8001", TimeoutSeconds = 5, ServiceApiKey = "test-service-key" }));

    private static MaintenanceCoordinationAgentRequest CreateRequest(MaintenanceRequestStatus status = MaintenanceRequestStatus.Submitted) => new()
    { MaintenanceRequestId = Guid.NewGuid(), Title = "Leak", Description = "Pipe leak", Category = "Plumbing", Priority = "High", CurrentStatus = status.ToString() };
    private static string SuccessJson(MaintenanceCoordinationAgentRequest request) => JsonSerializer.Serialize(MaintenanceCoordinationTestData.Response(request), JsonOptions);
    private static HttpResponseMessage JsonResponse(string json) => new(HttpStatusCode.OK) { Content = new StringContent(json, Encoding.UTF8, "application/json") };

    private sealed class StubHttpMessageHandler(Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>> sendAsync) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken) => sendAsync(request, cancellationToken);
    }
}
