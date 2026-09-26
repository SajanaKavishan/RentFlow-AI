using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using RentFlow.Api.Data;
using RentFlow.Api.DTOs.PricingAnalysis;
using RentFlow.Api.Models;
using RentFlow.Api.Services;
using Xunit;

namespace RentFlow.Api.Tests.Services;

public sealed class PricingAnalysisQueryServiceTests
{
    [Fact]
    public async Task GetByIdAsync_MapsApplicationResultAndOrdersSteps()
    {
        await using var context = CreateContext();
        var workflow = CreateWorkflow(Guid.NewGuid(), PricingAnalysisWorkflowStatus.Completed);
        workflow.ResultJson = JsonSerializer.Serialize(new PricingAnalysisResultDto
        {
            WorkflowId = workflow.Id,
            PropertyId = workflow.PropertyId,
            CurrentRent = 1200m,
            EvidenceSufficiency = PricingEvidenceSufficiency.MODERATE,
            Confidence = PricingConfidence.MEDIUM,
            UsableEvidenceCount = 3,
            SourceCounts = new PricingSourceCounts { LeaseAgreedRent = 1, RentalOffer = 2 },
            RecommendedMinRent = 1100m,
            RecommendedMaxRent = 1300m,
            CentralRecommendedRent = 1200m,
            Rationale = "Supplied evidence supports this advisory range.",
            CitedEvidenceRefs = ["cmp-001"],
            CitedEvidence = [new PricingAnalysisEvidenceSummaryDto
            {
                EvidenceRef = "cmp-001",
                SourceType = PricingEvidenceSourceType.LEASE_AGREED_RENT,
                MonthlyRent = 1150m,
                City = "Colombo",
                Bedrooms = 2,
                Bathrooms = 1,
                SourceStatus = "Active",
                EvidenceDate = DateTimeOffset.UtcNow,
                EvidenceStrength = PricingEvidenceStrength.HIGH
            }],
            Limitations = ["Based only on supplied evidence."],
            Warnings = [],
            AdvisoryOnly = true,
            EvidencePolicyVersion = "pricing-v1",
            AgentVersion = "pricing-agent-test"
        }, new JsonSerializerOptions(JsonSerializerDefaults.Web));
        workflow.Steps =
        [
            CreateStep(6, "produce_pricing_result"),
            CreateStep(1, "plan"),
            CreateStep(3, "collect_rental_evidence")
        ];
        context.PricingAnalysisWorkflows.Add(workflow);
        await context.SaveChangesAsync();

        var result = await new PricingAnalysisQueryService(context).GetByIdAsync(workflow.Id);

        Assert.NotNull(result);
        Assert.Equal(workflow.Id, result.WorkflowId);
        Assert.Equal(workflow.PropertyId, result.PropertyId);
        Assert.Equal(PricingAnalysisWorkflowStatus.Completed, result.Status);
        Assert.Equal("pricing-v1", result.EvidencePolicyVersion);
        Assert.Equal([1, 3, 6], result.Steps.Select(step => step.Order));
        Assert.Equal(1200m, result.Result!.CurrentRent);
        Assert.Equal("pricing-agent-test", result.Result.AgentVersion);
        Assert.Equal("cmp-001", Assert.Single(result.Result.CitedEvidenceRefs));
        Assert.Equal("Active", Assert.Single(result.Result.CitedEvidence).SourceStatus);
        Assert.True(result.Result.AdvisoryOnly);
        var responseJson = JsonSerializer.Serialize(result);
        Assert.DoesNotContain("resultJson", responseJson, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("sourcePropertyId", responseJson, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task GetByPropertyAsync_ReturnsOnlyThatPropertyHistoryInNewestFirstOrder()
    {
        await using var context = CreateContext();
        var propertyId = Guid.NewGuid();
        var otherPropertyId = Guid.NewGuid();
        var older = CreateWorkflow(propertyId, PricingAnalysisWorkflowStatus.Completed);
        older.CreatedAt = DateTimeOffset.UtcNow.AddDays(-1);
        older.Steps = [CreateStep(1, "plan")];
        var newer = CreateWorkflow(propertyId, PricingAnalysisWorkflowStatus.Failed);
        newer.CreatedAt = DateTimeOffset.UtcNow;
        newer.ErrorMessage = "The pricing analysis agent timed out.";
        newer.Steps = [CreateStep(2, "collect_property_facts")];
        var unrelated = CreateWorkflow(otherPropertyId, PricingAnalysisWorkflowStatus.Completed);
        context.PricingAnalysisWorkflows.AddRange(older, newer, unrelated);
        await context.SaveChangesAsync();

        var history = await new PricingAnalysisQueryService(context).GetByPropertyAsync(propertyId);

        Assert.Equal(2, history.Count);
        Assert.Equal(newer.Id, history[0].WorkflowId);
        Assert.Equal(older.Id, history[1].WorkflowId);
        Assert.Equal("The pricing analysis agent timed out.", history[0].ErrorMessage);
    }

    [Fact]
    public async Task GetByIdAsync_SanitizesUnknownFailureTextAndDoesNotExposeRawStepResults()
    {
        await using var context = CreateContext();
        var workflow = CreateWorkflow(Guid.NewGuid(), PricingAnalysisWorkflowStatus.Failed);
        workflow.ErrorMessage = "provider-secret stack trace and raw response";
        workflow.Steps =
        [
            new PricingAnalysisWorkflowStep
            {
                StepName = "analyse_pricing_evidence",
                StepOrder = 4,
                Status = PricingAnalysisWorkflowStepStatus.Failed,
                ErrorMessage = "provider-secret body"
            }
        ];
        workflow.Steps.Single().ResultJson = "{\"rawPrompt\":\"must not surface\"}";
        context.PricingAnalysisWorkflows.Add(workflow);
        await context.SaveChangesAsync();

        var result = await new PricingAnalysisQueryService(context).GetByIdAsync(workflow.Id);

        Assert.NotNull(result);
        Assert.Equal("The pricing analysis workflow failed unexpectedly.", result.ErrorMessage);
        Assert.Equal("The pricing analysis workflow failed unexpectedly.", Assert.Single(result.Steps).ErrorMessage);
        var responseJson = JsonSerializer.Serialize(result);
        Assert.DoesNotContain("provider-secret", responseJson, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("rawPrompt", responseJson, StringComparison.OrdinalIgnoreCase);
        Assert.Null(result.Result);
    }

    [Fact]
    public async Task GetByIdAsync_ReturnsNullForMissingWorkflow()
    {
        await using var context = CreateContext();
        Assert.Null(await new PricingAnalysisQueryService(context).GetByIdAsync(Guid.NewGuid()));
    }

    private static PricingAnalysisWorkflow CreateWorkflow(Guid propertyId, PricingAnalysisWorkflowStatus status) => new()
    {
        PropertyId = propertyId,
        Objective = "Analyze an evidence-supported monthly rental range.",
        EvidencePolicyVersion = "pricing-v1",
        Status = status
    };

    private static PricingAnalysisWorkflowStep CreateStep(int order, string name) => new()
    {
        StepOrder = order,
        StepName = name,
        Status = PricingAnalysisWorkflowStepStatus.Completed
    };

    private static ApplicationDbContext CreateContext() => new(new DbContextOptionsBuilder<ApplicationDbContext>()
        .UseInMemoryDatabase($"PricingAnalysisQuery-{Guid.NewGuid()}")
        .Options);
}
