using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;
using Microsoft.Extensions.Logging.Abstractions;
using RentFlow.Api.Data;
using RentFlow.Api.DTOs.PricingAnalysis;
using RentFlow.Api.Models;
using RentFlow.Api.Services;
using RentFlow.Api.Services.Interfaces;
using Xunit;

namespace RentFlow.Api.Tests.Services;

public sealed class PricingAnalysisOrchestratorTests
{
    private static readonly DateTimeOffset Now = new(2026, 9, 25, 8, 0, 0, TimeSpan.Zero);

    private static readonly string[] ExpectedSteps =
    [
        "plan",
        "collect_property_facts",
        "collect_rental_evidence",
        "analyse_pricing_evidence",
        "validate_pricing_recommendation",
        "produce_pricing_result"
    ];

    [Fact]
    public async Task StartAsync_CreatesFixedPendingPlanThenCompletesItWithPricingV1()
    {
        var observer = new InitialWorkflowObserver();
        await using var context = CreateContext(observer);
        var property = CreateProperty();
        context.Properties.Add(property);
        await context.SaveChangesAsync();
        var evidence = CreateEvidence(PricingEvidenceSufficiency.LIMITED);
        var agent = new FakePricingAgentClient();

        var result = await CreateOrchestrator(context, evidence, agent).StartAsync(property.Id);

        Assert.True(observer.SawInitialWorkflow);
        Assert.Equal(PricingAnalysisWorkflowStatus.Pending, observer.InitialWorkflowStatus);
        Assert.Equal(Enumerable.Repeat(PricingAnalysisWorkflowStepStatus.Pending, 6), observer.InitialStepStatuses);
        Assert.Equal("pricing-v1", result.EvidencePolicyVersion);
        Assert.Equal(PricingAnalysisWorkflowStatus.Completed, result.Status);
        Assert.Equal(6, result.Steps.Count);
        Assert.Equal(ExpectedSteps, result.Steps.Select(step => step.Name));
        Assert.Equal(Enumerable.Range(1, 6), result.Steps.Select(step => step.Order));
        Assert.All(result.Steps, step => Assert.Equal(PricingAnalysisWorkflowStepStatus.Completed, step.Status));
        Assert.Equal(property.Id, result.PropertyId);
    }

    [Theory]
    [InlineData(PricingEvidenceSufficiency.LIMITED)]
    [InlineData(PricingEvidenceSufficiency.MODERATE)]
    [InlineData(PricingEvidenceSufficiency.STRONG)]
    public async Task StartAsync_SufficientEvidenceCallsAgentOnceAndRetainsDeterministicAssessment(
        PricingEvidenceSufficiency sufficiency)
    {
        await using var context = CreateContext();
        var property = CreateProperty();
        context.Properties.Add(property);
        await context.SaveChangesAsync();
        var agent = new FakePricingAgentClient();

        var result = await CreateOrchestrator(context, CreateEvidence(sufficiency), agent).StartAsync(property.Id);

        Assert.Equal(1, agent.CallCount);
        Assert.Equal(sufficiency, result.EvidenceSufficiency);
        Assert.Equal(sufficiency is PricingEvidenceSufficiency.LIMITED
            ? PricingConfidence.LOW
            : PricingConfidence.MEDIUM, result.Confidence);
        Assert.Equal("pricing-v1", agent.LastRequest!.EvidencePolicyVersion);
        Assert.Equal(result.WorkflowId, agent.LastRequest.WorkflowId);
        Assert.Equal(property.Id, agent.LastRequest.PropertyId);
        Assert.Equal("test-pricing-agent-v1", result.Result!.AgentVersion);
        Assert.Equal("test-pricing-agent-v1", (await context.PricingAnalysisWorkflows.SingleAsync()).AgentVersion);
    }

    [Fact]
    public async Task StartAsync_GoldenComparableSetReachesAgentWithPersistedRoomFacts()
    {
        await using var context = CreateContext();
        var subject = CreateProperty();
        subject.Bathrooms = 2;
        subject.MonthlyRent = 90000m;
        subject.IsAvailable = true;
        subject.Area = 1000m;
        subject.AreaUnit = "sqft";
        var comparableData = new (int Bathrooms, decimal Area, decimal Rent)[]
        {
            (2, 950m, 120000m), (2, 1050m, 135000m),
            (2, 1100m, 155000m), (1, 850m, 100000m)
        };
        var comparables = comparableData.Select((item, index) => new Property
        {
            LandlordId = index % 2 == 0 ? Guid.NewGuid() : subject.LandlordId,
            Title = "Colombo comparable",
            Address = "Colombo",
            City = "Colombo",
            Bedrooms = 2,
            Bathrooms = item.Bathrooms,
            Area = item.Area,
            AreaUnit = "sqft",
            MonthlyRent = item.Rent,
            IsAvailable = true
        }).ToArray();
        context.Properties.AddRange([subject, .. comparables]);
        await context.SaveChangesAsync();
        var agent = new FakePricingAgentClient();

        var result = await CreateOrchestrator(
            context,
            [],
            agent,
            comparablesTool: new PricingComparableRentalsTool(context)).StartAsync(subject.Id);

        Assert.Equal(1, agent.CallCount);
        Assert.Equal(4, agent.LastRequest!.Comparables.Count);
        Assert.Equal(subject.Bathrooms, agent.LastRequest.PropertyFacts.Bathrooms);
        Assert.Equal(subject.Bedrooms, agent.LastRequest.PropertyFacts.Bedrooms);
        Assert.Equal(PricingEvidenceSufficiency.LIMITED, result.EvidenceSufficiency);
    }

    [Fact]
    public async Task StartAsync_InsufficientEvidenceSkipsAgentAndCompletesDeterministically()
    {
        await using var context = CreateContext();
        var property = CreateProperty();
        context.Properties.Add(property);
        await context.SaveChangesAsync();
        var agent = new FakePricingAgentClient();

        var result = await CreateOrchestrator(context, [], agent).StartAsync(property.Id);

        Assert.Equal(0, agent.CallCount);
        Assert.Equal(PricingAnalysisWorkflowStatus.Completed, result.Status);
        Assert.Equal(PricingEvidenceSufficiency.INSUFFICIENT, result.Result!.EvidenceSufficiency);
        Assert.Equal(PricingConfidence.LOW, result.Result.Confidence);
        Assert.Null(result.Result.RecommendedMinRent);
        Assert.Null(result.Result.RecommendedMaxRent);
        Assert.Null(result.Result.CentralRecommendedRent);
        Assert.Empty(result.Result.CitedEvidenceRefs);
        Assert.Empty(result.Result.CitedEvidence);
        Assert.Null(result.Result.AgentVersion);
        Assert.True(result.Result.AdvisoryOnly);
        Assert.Contains("insufficient", result.Result.Rationale, StringComparison.OrdinalIgnoreCase);
        Assert.NotEmpty(result.Result.Limitations);
        Assert.Equal(PricingAnalysisWorkflowStepStatus.Skipped, result.Steps.Single(step => step.Order == 4).Status);
        Assert.All(result.Steps.Where(step => step.Order != 4), step =>
            Assert.Equal(PricingAnalysisWorkflowStepStatus.Completed, step.Status));
    }

    [Fact]
    public async Task StartAsync_PersistsApplicationOwnedResultWithSafeEvidenceAndNoCurrencyOrMutation()
    {
        await using var context = CreateContext();
        var property = CreateProperty(monthlyRent: 1250m);
        context.Properties.Add(property);
        await context.SaveChangesAsync();
        var result = await CreateOrchestrator(
            context,
            CreateEvidence(PricingEvidenceSufficiency.LIMITED),
            new FakePricingAgentClient()).StartAsync(property.Id);

        var stored = await context.PricingAnalysisWorkflows
            .Include(workflow => workflow.Steps)
            .SingleAsync();
        using var document = JsonDocument.Parse(stored.ResultJson!);
        var json = stored.ResultJson!;

        Assert.Equal(1250m, result.Result!.CurrentRent);
        Assert.Equal(1250m, document.RootElement.GetProperty("currentRent").GetDecimal());
        Assert.True(result.Result.AdvisoryOnly);
        Assert.Equal("pricing-v1", result.Result.EvidencePolicyVersion);
        Assert.Contains("cmp-001", result.Result.CitedEvidenceRefs);
        Assert.Equal("Accepted", Assert.Single(result.Result.CitedEvidence).SourceStatus);
        Assert.DoesNotContain("currency", json, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("LKR", json, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("USD", json, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("prompt", json, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("provider-secret", json, StringComparison.OrdinalIgnoreCase);
        Assert.Equal(1250m, (await context.Properties.SingleAsync()).MonthlyRent);
        Assert.Empty(await context.RentalOffers.ToListAsync());
        Assert.Empty(await context.LeaseAgreements.ToListAsync());
        Assert.Empty(await context.Payments.ToListAsync());
        Assert.NotNull(stored.Steps.Single(step => step.StepOrder == 3).ResultJson);
        Assert.Equal(PricingAnalysisWorkflowStatus.Completed, stored.Status);
        Assert.Null(stored.ErrorMessage);
    }

    [Theory]
    [InlineData(PricingAnalysisAgentClientError.Configuration, "not configured correctly")]
    [InlineData(PricingAnalysisAgentClientError.Timeout, "timed out")]
    [InlineData(PricingAnalysisAgentClientError.ServiceUnavailable, "unavailable")]
    [InlineData(PricingAnalysisAgentClientError.UpstreamFailure, "unsuccessful response")]
    [InlineData(PricingAnalysisAgentClientError.MalformedResponse, "invalid response")]
    public async Task StartAsync_AgentFailuresLeaveSafeFailedAuditAndCompletedHistory(
        PricingAnalysisAgentClientError error,
        string safeText)
    {
        await using var context = CreateContext();
        var property = CreateProperty();
        context.Properties.Add(property);
        await context.SaveChangesAsync();
        var exception = new PricingAnalysisAgentClientException(error, "provider-secret raw body stack trace");
        var agent = new FakePricingAgentClient { Exception = exception };

        var result = await CreateOrchestrator(context, CreateEvidence(PricingEvidenceSufficiency.LIMITED), agent)
            .StartAsync(property.Id);

        Assert.Equal(1, agent.CallCount);
        Assert.Equal(PricingAnalysisWorkflowStatus.Failed, result.Status);
        Assert.Contains(safeText, result.ErrorMessage!, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("provider-secret", result.ErrorMessage, StringComparison.OrdinalIgnoreCase);
        Assert.Equal(PricingAnalysisWorkflowStepStatus.Failed, result.Steps.Single(step => step.Order == 4).Status);
        Assert.All(result.Steps.Where(step => step.Order < 4), step =>
            Assert.Equal(PricingAnalysisWorkflowStepStatus.Completed, step.Status));
        Assert.All(result.Steps.Where(step => step.Order > 4), step =>
            Assert.Equal(PricingAnalysisWorkflowStepStatus.Pending, step.Status));
        Assert.Null(result.Result);
        Assert.Null((await context.PricingAnalysisWorkflows.SingleAsync()).ResultJson);
    }

    [Fact]
    public async Task StartAsync_CallerCancellationIsPropagatedAndSafelyRecorded()
    {
        await using var context = CreateContext();
        var property = CreateProperty();
        context.Properties.Add(property);
        await context.SaveChangesAsync();
        using var cancellation = new CancellationTokenSource();
        var agent = new FakePricingAgentClient
        {
            OnAnalyze = token =>
            {
                cancellation.Cancel();
                return Task.FromCanceled<PricingAnalysisAgentResponse>(token);
            }
        };

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() =>
            CreateOrchestrator(context, CreateEvidence(PricingEvidenceSufficiency.LIMITED), agent)
                .StartAsync(property.Id, cancellation.Token));

        var workflow = await context.PricingAnalysisWorkflows.Include(item => item.Steps).SingleAsync();
        Assert.Equal(PricingAnalysisWorkflowStatus.Failed, workflow.Status);
        Assert.Equal(PricingAnalysisWorkflowStepStatus.Failed, workflow.Steps.Single(step => step.StepOrder == 4).Status);
        Assert.All(workflow.Steps.Where(step => step.StepOrder < 4), step =>
            Assert.Equal(PricingAnalysisWorkflowStepStatus.Completed, step.Status));
        Assert.DoesNotContain("stack", workflow.ErrorMessage!, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task StartAsync_MissingPropertyReturnsNotFoundWithoutCreatingWorkflow()
    {
        await using var context = CreateContext();
        var exception = await Assert.ThrowsAsync<PricingAnalysisException>(() =>
            CreateOrchestrator(context, [], new FakePricingAgentClient()).StartAsync(Guid.NewGuid()));

        Assert.Equal(PricingAnalysisError.NotFound, exception.Error);
        Assert.Empty(await context.PricingAnalysisWorkflows.ToListAsync());
    }

    [Fact]
    public async Task StartAsync_PropertyFactsToolMissingSubjectSafelyFailsCurrentStep()
    {
        await using var context = CreateContext();
        var property = CreateProperty();
        context.Properties.Add(property);
        await context.SaveChangesAsync();
        var agent = new FakePricingAgentClient();

        var result = await CreateOrchestrator(
            context,
            CreateEvidence(PricingEvidenceSufficiency.LIMITED),
            agent,
            factsTool: new MissingPropertyFactsTool()).StartAsync(property.Id);

        Assert.Equal(PricingAnalysisWorkflowStatus.Failed, result.Status);
        Assert.Equal(PricingAnalysisWorkflowStepStatus.Completed, result.Steps.Single(step => step.Order == 1).Status);
        Assert.Equal(PricingAnalysisWorkflowStepStatus.Failed, result.Steps.Single(step => step.Order == 2).Status);
        Assert.All(result.Steps.Where(step => step.Order > 2), step =>
            Assert.Equal(PricingAnalysisWorkflowStepStatus.Pending, step.Status));
        Assert.Equal(0, agent.CallCount);
        Assert.Equal("The pricing analysis step failed unexpectedly.", result.ErrorMessage);
    }

    [Fact]
    public async Task StartAsync_EvidenceToolFailurePreservesEarlierCompletedSteps()
    {
        await using var context = CreateContext();
        var property = CreateProperty();
        context.Properties.Add(property);
        await context.SaveChangesAsync();
        var agent = new FakePricingAgentClient();

        var result = await CreateOrchestrator(
            context,
            [],
            agent,
            comparablesTool: new ThrowingComparableTool()).StartAsync(property.Id);

        Assert.Equal(PricingAnalysisWorkflowStatus.Failed, result.Status);
        Assert.Equal(PricingAnalysisWorkflowStepStatus.Completed, result.Steps.Single(step => step.Order == 1).Status);
        Assert.Equal(PricingAnalysisWorkflowStepStatus.Completed, result.Steps.Single(step => step.Order == 2).Status);
        Assert.Equal(PricingAnalysisWorkflowStepStatus.Failed, result.Steps.Single(step => step.Order == 3).Status);
        Assert.Equal(0, agent.CallCount);
    }

    [Fact]
    public async Task StartAsync_RevalidatesResponseBeforePersistingAgentVersion()
    {
        await using var context = CreateContext();
        var property = CreateProperty();
        context.Properties.Add(property);
        await context.SaveChangesAsync();
        var agent = new FakePricingAgentClient
        {
            ResponseFactory = request =>
            {
                var response = FakePricingAgentClient.ValidResponse(request);
                return new PricingAnalysisAgentResponse
                {
                    WorkflowId = Guid.NewGuid(),
                    PropertyId = response.PropertyId,
                    AgentVersion = response.AgentVersion,
                    ModelDraft = response.ModelDraft,
                    ExecutionMetadata = response.ExecutionMetadata
                };
            }
        };

        var result = await CreateOrchestrator(context, CreateEvidence(PricingEvidenceSufficiency.LIMITED), agent)
            .StartAsync(property.Id);

        Assert.Equal(PricingAnalysisWorkflowStatus.Failed, result.Status);
        Assert.Equal(PricingAnalysisWorkflowStepStatus.Completed, result.Steps.Single(step => step.Order == 4).Status);
        Assert.Equal(PricingAnalysisWorkflowStepStatus.Failed, result.Steps.Single(step => step.Order == 5).Status);
        Assert.Null((await context.PricingAnalysisWorkflows.SingleAsync()).AgentVersion);
        Assert.DoesNotContain("provider", result.ErrorMessage!, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task StartAsync_InvalidPropertyIdIsRejected()
    {
        await using var context = CreateContext();
        var exception = await Assert.ThrowsAsync<PricingAnalysisException>(() =>
            CreateOrchestrator(context, [], new FakePricingAgentClient()).StartAsync(Guid.Empty));
        Assert.Equal(PricingAnalysisError.Validation, exception.Error);
    }

    private static PricingAnalysisOrchestrator CreateOrchestrator(
        ApplicationDbContext context,
        IReadOnlyCollection<PricingComparableEvidence> evidence,
        FakePricingAgentClient agent,
        IPricingPropertyFactsTool? factsTool = null,
        IPricingComparableRentalsTool? comparablesTool = null) => new(
            context,
            factsTool ?? new PricingPropertyFactsTool(context, new FixedTimeProvider(Now)),
            comparablesTool ?? new FakeComparableTool(evidence),
            new PricingEvidenceAssessmentTool(),
            agent,
            new FixedTimeProvider(Now),
            NullLogger<PricingAnalysisOrchestrator>.Instance);

    private static IReadOnlyCollection<PricingComparableEvidence> CreateEvidence(
        PricingEvidenceSufficiency sufficiency)
    {
        var count = sufficiency switch
        {
            PricingEvidenceSufficiency.INSUFFICIENT => 0,
            PricingEvidenceSufficiency.LIMITED => 1,
            PricingEvidenceSufficiency.MODERATE => 3,
            PricingEvidenceSufficiency.STRONG => 5,
            _ => 0
        };
        return Enumerable.Range(0, count)
            .Select(index =>
            {
                var leaseCount = sufficiency switch
                {
                    PricingEvidenceSufficiency.MODERATE => index == 0 ? 1 : 0,
                    PricingEvidenceSufficiency.STRONG => index < 3 ? 1 : 0,
                    _ => 0
                };
                return new PricingComparableEvidence
                {
                    EvidenceRef = $"cmp-{index + 1:000}",
                    SourceType = leaseCount == 1
                        ? PricingEvidenceSourceType.LEASE_AGREED_RENT
                        : PricingEvidenceSourceType.RENTAL_OFFER,
                    MonthlyRent = 1050m + index * 50m,
                    City = "Colombo",
                    Bedrooms = 2,
                    Bathrooms = 1,
                    SourceStatus = leaseCount == 1 ? "Active" : "Accepted",
                    EvidenceDate = Now.AddDays(-index),
                    EvidenceStrength = leaseCount == 1
                        ? PricingEvidenceStrength.HIGH
                        : PricingEvidenceStrength.MEDIUM
                };
            })
            .ToArray();
    }

    private static Property CreateProperty(decimal monthlyRent = 1250m) => new()
    {
        LandlordId = Guid.NewGuid(),
        Title = "Two bedroom property",
        Description = "Private description not included in pricing Agent inputs.",
        Address = "Private address",
        City = "Colombo",
        MonthlyRent = monthlyRent,
        Bedrooms = 2,
        Bathrooms = 1
    };

    private static ApplicationDbContext CreateContext(InitialWorkflowObserver? observer = null)
    {
        var builder = new DbContextOptionsBuilder<ApplicationDbContext>()
            .UseInMemoryDatabase($"PricingAnalysisOrchestrator-{Guid.NewGuid()}");
        if (observer is not null)
        {
            builder.AddInterceptors(observer);
        }
        return new ApplicationDbContext(builder.Options);
    }

    private sealed class FakeComparableTool(IReadOnlyCollection<PricingComparableEvidence> evidence)
        : IPricingComparableRentalsTool
    {
        public Task<IReadOnlyCollection<PricingComparableEvidence>> GetAsync(
            PricingEvidenceScope subject,
            CancellationToken cancellationToken = default)
        {
            cancellationToken.ThrowIfCancellationRequested();
            Assert.NotEqual(Guid.Empty, subject.SubjectLandlordId);
            return Task.FromResult(evidence);
        }
    }

    private sealed class ThrowingComparableTool : IPricingComparableRentalsTool
    {
        public Task<IReadOnlyCollection<PricingComparableEvidence>> GetAsync(
            PricingEvidenceScope subject,
            CancellationToken cancellationToken = default) =>
            throw new InvalidOperationException("private database connection string");
    }

    private sealed class MissingPropertyFactsTool : IPricingPropertyFactsTool
    {
        public Task<PricingEvidenceScope?> GetAsync(
            Guid propertyId,
            CancellationToken cancellationToken = default) => Task.FromResult<PricingEvidenceScope?>(null);
    }

    private sealed class FakePricingAgentClient : IPricingAnalysisAgentClient
    {
        public int CallCount { get; private set; }

        public PricingAnalysisAgentRequest? LastRequest { get; private set; }

        public Exception? Exception { get; init; }

        public Func<CancellationToken, Task<PricingAnalysisAgentResponse>>? OnAnalyze { get; init; }

        public Func<PricingAnalysisAgentRequest, PricingAnalysisAgentResponse>? ResponseFactory { get; init; }

        public Task<PricingAnalysisAgentResponse> AnalyzeAsync(
            PricingAnalysisAgentRequest request,
            CancellationToken cancellationToken = default)
        {
            CallCount++;
            LastRequest = request;
            if (OnAnalyze is not null)
            {
                return OnAnalyze(cancellationToken);
            }
            if (Exception is not null)
            {
                return Task.FromException<PricingAnalysisAgentResponse>(Exception);
            }

            return Task.FromResult(ResponseFactory?.Invoke(request) ?? ValidResponse(request));
        }

        public static PricingAnalysisAgentResponse ValidResponse(PricingAnalysisAgentRequest request)
        {
            var refs = request.Comparables.Select(item => item.EvidenceRef).ToArray();
            return new PricingAnalysisAgentResponse
            {
                WorkflowId = request.WorkflowId,
                PropertyId = request.PropertyId,
                AgentVersion = "test-pricing-agent-v1",
                ModelDraft = new PricingAnalysisAgentModelDraft
                {
                    RecommendedMinRent = 1100m,
                    RecommendedMaxRent = 1350m,
                    CentralRecommendedRent = 1225m,
                    CitedEvidenceRefs = refs,
                    Rationale = "Comparable evidence supports this advisory range.",
                    Limitations = ["Recommendations depend on supplied comparable evidence."],
                    Warnings = []
                },
                ExecutionMetadata = new PricingAnalysisAgentExecutionMetadata
                {
                    WorkflowPlanVersion = "pricing-v1",
                    ExpectedSteps = ExpectedSteps,
                    ExecutedSteps = ExpectedSteps,
                    SkippedSteps = []
                }
            };
        }
    }

    private sealed class FixedTimeProvider(DateTimeOffset now) : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() => now;
    }

    private sealed class InitialWorkflowObserver : SaveChangesInterceptor
    {
        public bool SawInitialWorkflow { get; private set; }

        public PricingAnalysisWorkflowStatus? InitialWorkflowStatus { get; private set; }

        public PricingAnalysisWorkflowStepStatus[] InitialStepStatuses { get; private set; } = [];

        public override ValueTask<InterceptionResult<int>> SavingChangesAsync(
            DbContextEventData eventData,
            InterceptionResult<int> result,
            CancellationToken cancellationToken = default)
        {
            if (!SawInitialWorkflow && eventData.Context is ApplicationDbContext context)
            {
                var workflow = context.PricingAnalysisWorkflows.Local.SingleOrDefault();
                if (workflow is not null)
                {
                    SawInitialWorkflow = true;
                    InitialWorkflowStatus = workflow.Status;
                    InitialStepStatuses = workflow.Steps.OrderBy(step => step.StepOrder)
                        .Select(step => step.Status)
                        .ToArray();
                }
            }
            return ValueTask.FromResult(result);
        }
    }
}
