using System.Net;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.Extensions.Options;
using RentFlow.Api.Configuration;
using RentFlow.Api.DTOs.PricingAnalysis;
using RentFlow.Api.Models;
using RentFlow.Api.Services;
using Xunit;

namespace RentFlow.Api.Tests.Services;

public sealed class PricingAnalysisAgentClientTests
{
    private static readonly JsonSerializerOptions WebJson = new(JsonSerializerDefaults.Web);

    [Fact]
    public async Task SendsPostToExactPricingEndpointUsingApprovedCamelCaseRequestAndStringEnums()
    {
        var request = CreateRequest();
        JsonDocument? body = null;
        var handler = new StubHttpMessageHandler(async (message, cancellationToken) =>
        {
            Assert.Equal(HttpMethod.Post, message.Method);
            Assert.Equal("/internal/pricing-analysis/analyze", message.RequestUri!.AbsolutePath);
            body = JsonDocument.Parse(await message.Content!.ReadAsStringAsync(cancellationToken));
            return JsonResponse(Serialize(CreateResponse(request)));
        });

        await CreateClient(handler).AnalyzeAsync(request);

        Assert.NotNull(body);
        var root = body.RootElement;
        Assert.Equal(request.WorkflowId, root.GetProperty("workflowId").GetGuid());
        Assert.Equal(request.PropertyId, root.GetProperty("propertyId").GetGuid());
        Assert.Equal("Analyze an evidence-supported monthly rental range.", root.GetProperty("objective").GetString());
        Assert.Equal("pricing-v1", root.GetProperty("evidencePolicyVersion").GetString());
        Assert.False(root.GetProperty("propertyFacts").TryGetProperty("propertyId", out _));
        Assert.True(root.GetProperty("propertyFacts").TryGetProperty("snapshotAt", out _));
        Assert.Equal("RENTAL_OFFER", root.GetProperty("comparables")[0].GetProperty("sourceType").GetString());
        Assert.Equal("MEDIUM", root.GetProperty("comparables")[0].GetProperty("evidenceStrength").GetString());
        Assert.Equal("OTHER_PROPERTY", root.GetProperty("comparables")[0].GetProperty("relationshipToSubject").GetString());
        Assert.Equal("LIMITED", root.GetProperty("deterministicAssessment").GetProperty("evidenceSufficiency").GetString());
        Assert.Equal("LOW", root.GetProperty("deterministicAssessment").GetProperty("confidence").GetString());
        Assert.Equal(1, root.GetProperty("deterministicAssessment").GetProperty("sourceCounts").GetProperty("rentalOffer").GetInt32());
        Assert.False(root.GetProperty("deterministicAssessment").TryGetProperty("findings", out _));
        Assert.False(root.GetProperty("deterministicAssessment").TryGetProperty("numericalRecommendationAllowed", out _));
        Assert.False(root.TryGetProperty("landlordId", out _));
        Assert.False(root.TryGetProperty("currency", out _));
        Assert.False(root.GetProperty("propertyFacts").TryGetProperty("address", out _));
        body.Dispose();
    }

    [Theory]
    [InlineData(PricingEvidenceSufficiency.INSUFFICIENT, "INSUFFICIENT")]
    [InlineData(PricingEvidenceSufficiency.LIMITED, "LIMITED")]
    [InlineData(PricingEvidenceSufficiency.MODERATE, "MODERATE")]
    [InlineData(PricingEvidenceSufficiency.STRONG, "STRONG")]
    public async Task RequestSerializesEveryEvidenceSufficiencyAsItsPythonString(
        PricingEvidenceSufficiency sufficiency,
        string expected)
    {
        var request = CreateRequest(sufficiency);
        string? body = null;
        var handler = new StubHttpMessageHandler(async (message, token) =>
        {
            body = await message.Content!.ReadAsStringAsync(token);
            return JsonResponse(Serialize(CreateResponse(request)));
        });

        await CreateClient(handler).AnalyzeAsync(request);

        using var document = JsonDocument.Parse(body!);
        Assert.Equal(expected, document.RootElement.GetProperty("deterministicAssessment")
            .GetProperty("evidenceSufficiency").GetString());
        Assert.DoesNotContain("\"evidenceSufficiency\":0", body, StringComparison.Ordinal);
    }

    [Theory]
    [InlineData(PricingEvidenceSourceType.LISTING_ASKING_RENT, "Available", PricingEvidenceStrength.LOW, "LISTING_ASKING_RENT", "LOW")]
    [InlineData(PricingEvidenceSourceType.RENTAL_OFFER, "Accepted", PricingEvidenceStrength.MEDIUM, "RENTAL_OFFER", "MEDIUM")]
    [InlineData(PricingEvidenceSourceType.LEASE_AGREED_RENT, "Active", PricingEvidenceStrength.HIGH, "LEASE_AGREED_RENT", "HIGH")]
    public async Task RequestSerializesEachSourceAndStrengthEnumAsPythonStrings(
        PricingEvidenceSourceType sourceType,
        string status,
        PricingEvidenceStrength strength,
        string expectedSource,
        string expectedStrength)
    {
        var request = CreateRequest(sourceType: sourceType, sourceStatus: status, strength: strength);
        string? body = null;
        var handler = new StubHttpMessageHandler(async (message, token) =>
        {
            body = await message.Content!.ReadAsStringAsync(token);
            return JsonResponse(Serialize(CreateResponse(request)));
        });

        await CreateClient(handler).AnalyzeAsync(request);

        using var document = JsonDocument.Parse(body!);
        var comparable = document.RootElement.GetProperty("comparables")[0];
        Assert.Equal(expectedSource, comparable.GetProperty("sourceType").GetString());
        Assert.Equal(expectedStrength, comparable.GetProperty("evidenceStrength").GetString());
    }

    [Theory]
    [InlineData(PricingEvidenceSufficiency.LIMITED)]
    [InlineData(PricingEvidenceSufficiency.MODERATE)]
    [InlineData(PricingEvidenceSufficiency.STRONG)]
    [InlineData(PricingEvidenceSufficiency.INSUFFICIENT)]
    public async Task AcceptsValidResponseForEveryEvidenceSufficiency(PricingEvidenceSufficiency sufficiency)
    {
        var request = CreateRequest(sufficiency);
        var result = await CreateClient(new StubHttpMessageHandler((_, _) => Task.FromResult(
            JsonResponse(Serialize(CreateResponse(request)))))).AnalyzeAsync(request);

        Assert.Equal(request.WorkflowId, result.WorkflowId);
        Assert.Equal(request.PropertyId, result.PropertyId);
        Assert.Equal("python-agent-v1", result.AgentVersion);
    }

    [Fact]
    public async Task RejectsNullResponse()
    {
        var request = CreateRequest();
        await AssertMalformed(request, "null");
    }

    [Fact]
    public async Task RejectsMalformedJson()
    {
        var request = CreateRequest();
        await AssertMalformed(request, "{ malformed");
    }

    [Theory]
    [InlineData("workflowId")]
    [InlineData("propertyId")]
    public async Task RejectsMismatchedIdentity(string identity)
    {
        var request = CreateRequest();
        var node = CreateResponseNode(request);
        node[identity] = Guid.NewGuid().ToString();
        await AssertMalformed(request, node.ToJsonString());
    }

    [Fact]
    public async Task RejectsMissingAndBlankAgentVersion()
    {
        var request = CreateRequest();
        var missing = CreateResponseNode(request);
        missing.AsObject().Remove("agentVersion");
        await AssertMalformed(request, missing.ToJsonString());

        var blank = CreateResponseNode(request);
        blank["agentVersion"] = "  ";
        await AssertMalformed(request, blank.ToJsonString());
    }

    [Fact]
    public async Task RejectsMissingModelDraft()
    {
        var request = CreateRequest();
        var node = CreateResponseNode(request);
        node["modelDraft"] = null;
        await AssertMalformed(request, node.ToJsonString());
    }

    [Theory]
    [InlineData("unknown")]
    [InlineData("duplicate")]
    public async Task RejectsUnknownOrDuplicateEvidenceReferences(string kind)
    {
        var request = CreateRequest();
        var node = CreateResponseNode(request);
        node["modelDraft"]!["citedEvidenceRefs"] = kind == "unknown"
            ? new JsonArray("not-supplied")
            : new JsonArray("cmp-001", "cmp-001");
        await AssertMalformed(request, node.ToJsonString());
    }

    [Theory]
    [InlineData("minWithoutMax")]
    [InlineData("maxWithoutMin")]
    [InlineData("minGreaterThanMax")]
    [InlineData("nonpositive")]
    [InlineData("unsupportedPrecision")]
    [InlineData("unsupportedRange")]
    [InlineData("centralBelowMin")]
    [InlineData("centralAboveMax")]
    public async Task RejectsInvalidRecommendationGroupsAndRanges(string invalidCase)
    {
        var request = CreateRequest();
        var node = CreateResponseNode(request);
        var draft = node["modelDraft"]!;
        switch (invalidCase)
        {
            case "minWithoutMax":
                draft["recommendedMaxRent"] = null;
                break;
            case "maxWithoutMin":
                draft["recommendedMinRent"] = null;
                break;
            case "minGreaterThanMax":
                draft["recommendedMinRent"] = 1300;
                draft["recommendedMaxRent"] = 1200;
                break;
            case "nonpositive":
                draft["recommendedMinRent"] = 0;
                break;
            case "unsupportedPrecision":
                draft["recommendedMinRent"] = 1000.001m;
                break;
            case "unsupportedRange":
                draft["recommendedMinRent"] = 10000000000000000m;
                break;
            case "centralBelowMin":
                draft["centralRecommendedRent"] = 999;
                break;
            case "centralAboveMax":
                draft["centralRecommendedRent"] = 1201;
                break;
        }

        await AssertMalformed(request, node.ToJsonString());
    }

    [Fact]
    public async Task RejectsInsufficientResponseContainingRecommendationOrCitations()
    {
        var request = CreateRequest(PricingEvidenceSufficiency.INSUFFICIENT);
        var node = CreateResponseNode(request);
        node["modelDraft"]!["recommendedMinRent"] = 1000;
        node["modelDraft"]!["recommendedMaxRent"] = 1200;
        node["modelDraft"]!["citedEvidenceRefs"] = new JsonArray("cmp-001");
        await AssertMalformed(request, node.ToJsonString());
    }

    [Fact]
    public async Task RejectsInsufficientResponseWithInvalidExecutionMetadata()
    {
        var request = CreateRequest(PricingEvidenceSufficiency.INSUFFICIENT);
        var node = CreateResponseNode(request);
        node["executionMetadata"]!["executedSteps"] = new JsonArray("plan", "analyse_pricing_evidence");
        await AssertMalformed(request, node.ToJsonString());
    }

    [Fact]
    public async Task RejectsNonInsufficientResponseThatSkipsAnalysis()
    {
        var request = CreateRequest();
        var node = CreateResponseNode(request);
        node["executionMetadata"]!["skippedSteps"] = new JsonArray("analyse_pricing_evidence");
        await AssertMalformed(request, node.ToJsonString());
    }

    [Theory]
    [InlineData("planVersion")]
    [InlineData("expectedStepOrder")]
    [InlineData("unexpectedStep")]
    [InlineData("missingExpectedStep")]
    public async Task RejectsExecutionPlanAndStepMetadataMismatch(string invalidCase)
    {
        var request = CreateRequest();
        var node = CreateResponseNode(request);
        var metadata = node["executionMetadata"]!;
        switch (invalidCase)
        {
            case "planVersion":
                metadata["workflowPlanVersion"] = "other-v1";
                break;
            case "expectedStepOrder":
                metadata["expectedSteps"]![0] = "collect_property_facts";
                break;
            case "unexpectedStep":
                metadata["executedSteps"]![3] = "unexpected_step";
                break;
            case "missingExpectedStep":
                metadata["executedSteps"]!.AsArray().RemoveAt(3);
                break;
        }

        await AssertMalformed(request, node.ToJsonString());
    }

    [Fact]
    public async Task MapsUpstreamFailureWithoutReadingOrExposingBody()
    {
        const string sensitiveBody = "provider-secret raw prompt hidden reasoning";
        var handler = new StubHttpMessageHandler((_, _) => Task.FromResult(
            new HttpResponseMessage(HttpStatusCode.BadGateway)
            {
                Content = new StringContent(sensitiveBody)
            }));
        var exception = await Assert.ThrowsAsync<PricingAnalysisAgentClientException>(() =>
            CreateClient(handler).AnalyzeAsync(CreateRequest()));

        Assert.Equal(PricingAnalysisAgentClientError.UpstreamFailure, exception.Error);
        Assert.DoesNotContain(sensitiveBody, exception.Message, StringComparison.Ordinal);
    }

    [Fact]
    public async Task MapsHttpRequestExceptionToSanitizedServiceUnavailable()
    {
        var handler = new StubHttpMessageHandler((_, _) =>
            throw new HttpRequestException("provider-secret-and-stack"));
        var exception = await Assert.ThrowsAsync<PricingAnalysisAgentClientException>(() =>
            CreateClient(handler).AnalyzeAsync(CreateRequest()));

        Assert.Equal(PricingAnalysisAgentClientError.ServiceUnavailable, exception.Error);
        Assert.DoesNotContain("provider-secret", exception.Message, StringComparison.Ordinal);
        Assert.Null(exception.InnerException);
    }

    [Fact]
    public async Task MapsConfiguredTimeoutToPricingTimeoutError()
    {
        var handler = new StubHttpMessageHandler(async (_, token) =>
        {
            await Task.Delay(Timeout.InfiniteTimeSpan, token);
            throw new InvalidOperationException("Unreachable");
        });
        var exception = await Assert.ThrowsAsync<PricingAnalysisAgentClientException>(() =>
            CreateClient(handler, timeoutSeconds: 1).AnalyzeAsync(CreateRequest()));

        Assert.Equal(PricingAnalysisAgentClientError.Timeout, exception.Error);
    }

    [Fact]
    public async Task CallerCancellationPropagatesAsCancellation()
    {
        var handler = new StubHttpMessageHandler(async (_, token) =>
        {
            await Task.Delay(Timeout.InfiniteTimeSpan, token);
            throw new InvalidOperationException("Unreachable");
        });
        using var cancellation = new CancellationTokenSource(TimeSpan.FromMilliseconds(100));

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() =>
            CreateClient(handler).AnalyzeAsync(CreateRequest(), cancellation.Token));
    }

    [Theory]
    [InlineData("not a uri", 10)]
    [InlineData("/relative/path", 10)]
    [InlineData("ftp://agent.example", 10)]
    [InlineData("http://agent.example", 0)]
    [InlineData("http://agent.example", 301)]
    public async Task RejectsInvalidAgentServiceConfiguration(string baseUrl, int timeoutSeconds)
    {
        var exception = await Assert.ThrowsAsync<PricingAnalysisAgentClientException>(() =>
            CreateClient(new StubHttpMessageHandler((_, _) => throw new InvalidOperationException()), baseUrl, timeoutSeconds)
                .AnalyzeAsync(CreateRequest()));

        Assert.Equal(PricingAnalysisAgentClientError.Configuration, exception.Error);
    }

    [Theory]
    [InlineData("currency")]
    [InlineData("requiresApproval")]
    [InlineData("applyRentMutation")]
    public async Task RejectsUnmappedCurrencyApprovalAndMutationFields(string field)
    {
        var request = CreateRequest();
        var node = CreateResponseNode(request);
        node[field] = "unexpected";
        await AssertMalformed(request, node.ToJsonString());
    }

    [Fact]
    public async Task RejectsUnknownNestedResponseMembers()
    {
        var request = CreateRequest();
        var node = CreateResponseNode(request);
        node["modelDraft"]!["currency"] = "LKR";
        await AssertMalformed(request, node.ToJsonString());
    }

    [Fact]
    public void RequestMapperOmitsNonContractStageTwoAFieldsAndUsesCanonicalPolicy()
    {
        var mapped = CreateRequest();
        Assert.Equal("pricing-v1", mapped.EvidencePolicyVersion);
        Assert.Equal("OTHER_PROPERTY", Assert.Single(mapped.Comparables).RelationshipToSubject);

        var root = JsonNode.Parse(JsonSerializer.Serialize(mapped, WebJson))!;
        Assert.Null(root["propertyFacts"]!["propertyId"]);
        Assert.Null(root["deterministicAssessment"]!["findings"]);
        Assert.Null(root["deterministicAssessment"]!["limitations"]);
        Assert.Null(root["deterministicAssessment"]!["numericalRecommendationAllowed"]);
    }

    private static async Task AssertMalformed(PricingAnalysisAgentRequest request, string body)
    {
        var exception = await Assert.ThrowsAsync<PricingAnalysisAgentClientException>(() =>
            CreateClient(new StubHttpMessageHandler((_, _) => Task.FromResult(JsonResponse(body))))
                .AnalyzeAsync(request));
        Assert.Equal(PricingAnalysisAgentClientError.MalformedResponse, exception.Error);
        Assert.DoesNotContain("hidden", exception.Message, StringComparison.OrdinalIgnoreCase);
    }

    private static PricingAnalysisAgentRequest CreateRequest(
        PricingEvidenceSufficiency sufficiency = PricingEvidenceSufficiency.LIMITED,
        PricingEvidenceSourceType sourceType = PricingEvidenceSourceType.RENTAL_OFFER,
        string sourceStatus = "Accepted",
        PricingEvidenceStrength strength = PricingEvidenceStrength.MEDIUM)
    {
        var workflowId = Guid.NewGuid();
        var propertyId = Guid.NewGuid();
        var comparableCount = sufficiency == PricingEvidenceSufficiency.INSUFFICIENT ? 0 : 1;
        var comparables = comparableCount == 0
            ? Array.Empty<PricingComparableEvidence>()
            :
            [
                new PricingComparableEvidence
                {
                    EvidenceRef = "cmp-001",
                    SourceType = sourceType,
                    MonthlyRent = 1100m,
                    City = "Colombo",
                    Bedrooms = 2,
                    Bathrooms = 1,
                    SourceStatus = sourceStatus,
                    EvidenceDate = DateTimeOffset.Parse("2026-09-01T00:00:00Z"),
                    EvidenceStrength = strength
                }
            ];
        var sourceCounts = new PricingSourceCounts
        {
            ListingAskingRent = sourceType == PricingEvidenceSourceType.LISTING_ASKING_RENT ? comparableCount : 0,
            RentalOffer = sourceType == PricingEvidenceSourceType.RENTAL_OFFER ? comparableCount : 0,
            LeaseAgreedRent = sourceType == PricingEvidenceSourceType.LEASE_AGREED_RENT ? comparableCount : 0
        };

        return PricingAnalysisRequestMapper.Create(
            workflowId,
            propertyId,
            "Analyze an evidence-supported monthly rental range.",
            new PricingPropertyFacts
            {
                PropertyId = propertyId,
                City = "Colombo",
                MonthlyRent = 1250m,
                Bedrooms = 2,
                Bathrooms = 1,
                IsAvailable = true,
                SnapshotAt = DateTimeOffset.Parse("2026-09-25T00:00:00Z")
            },
            comparables,
            new PricingDeterministicAssessment
            {
                EvidenceSufficiency = sufficiency,
                Confidence = sufficiency is PricingEvidenceSufficiency.STRONG or PricingEvidenceSufficiency.MODERATE
                    ? PricingConfidence.MEDIUM
                    : PricingConfidence.LOW,
                UsableEvidenceCount = comparableCount,
                SourceCounts = sourceCounts,
                NumericalRecommendationAllowed = comparableCount > 0,
                Findings = ["Deterministically assessed."],
                Limitations = []
            },
            "pricing-v1");
    }

    private static PricingAnalysisAgentResponse CreateResponse(PricingAnalysisAgentRequest request)
    {
        var insufficient = request.DeterministicAssessment.EvidenceSufficiency
            == PricingEvidenceSufficiency.INSUFFICIENT;
        return new PricingAnalysisAgentResponse
        {
            WorkflowId = request.WorkflowId,
            PropertyId = request.PropertyId,
            AgentVersion = "python-agent-v1",
            ModelDraft = new PricingAnalysisAgentModelDraft
            {
                RecommendedMinRent = insufficient ? null : 1000m,
                RecommendedMaxRent = insufficient ? null : 1200m,
                CentralRecommendedRent = insufficient ? null : 1100m,
                CitedEvidenceRefs = insufficient ? [] : ["cmp-001"],
                Rationale = insufficient
                    ? "The supplied evidence is insufficient to support a numerical rental recommendation."
                    : "Comparable evidence supports this advisory range.",
                Limitations = ["This is advisory only."],
                Warnings = []
            },
            ExecutionMetadata = new PricingAnalysisAgentExecutionMetadata
            {
                WorkflowPlanVersion = "pricing-v1",
                ExpectedSteps = ExpectedSteps,
                ExecutedSteps = insufficient
                    ? ExpectedSteps.Where(step => step != "analyse_pricing_evidence").ToArray()
                    : ExpectedSteps,
                SkippedSteps = insufficient ? ["analyse_pricing_evidence"] : []
            }
        };
    }

    private static JsonNode CreateResponseNode(PricingAnalysisAgentRequest request) =>
        JsonNode.Parse(Serialize(CreateResponse(request)))!;

    private static string Serialize(PricingAnalysisAgentResponse response) =>
        JsonSerializer.Serialize(response, WebJson);

    private static readonly string[] ExpectedSteps =
    [
        "plan",
        "collect_property_facts",
        "collect_rental_evidence",
        "analyse_pricing_evidence",
        "validate_pricing_recommendation",
        "produce_pricing_result"
    ];

    private static PricingAnalysisAgentClient CreateClient(
        StubHttpMessageHandler handler,
        string baseUrl = "http://agent.internal:8001",
        int timeoutSeconds = 5) =>
        new(new HttpClient(handler), Options.Create(new AgentServiceOptions
        {
            BaseUrl = baseUrl,
            TimeoutSeconds = timeoutSeconds
        }));

    private static HttpResponseMessage JsonResponse(string json) => new(HttpStatusCode.OK)
    {
        Content = new StringContent(json, Encoding.UTF8, "application/json")
    };

    private sealed class StubHttpMessageHandler(
        Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>> sendAsync) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            CancellationToken cancellationToken) => sendAsync(request, cancellationToken);
    }
}
