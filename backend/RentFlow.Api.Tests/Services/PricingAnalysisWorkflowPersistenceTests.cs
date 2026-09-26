using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Metadata;
using RentFlow.Api.Data;
using RentFlow.Api.DTOs.PricingAnalysis;
using RentFlow.Api.Models;
using Xunit;

namespace RentFlow.Api.Tests.Services;

public sealed class PricingAnalysisWorkflowPersistenceTests
{
    private static readonly string[] StepNames =
    [
        "plan",
        "collect_property_facts",
        "collect_rental_evidence",
        "analyse_pricing_evidence",
        "validate_pricing_recommendation",
        "produce_pricing_result"
    ];

    [Fact]
    public async Task PersistsPricingWorkflowAndStructuredAuditResult()
    {
        await using var context = CreateContext();
        var property = CreateProperty();
        context.Properties.Add(property);
        await context.SaveChangesAsync();

        var workflow = new PricingAnalysisWorkflow
        {
            PropertyId = property.Id,
            Objective = "Assess an advisory rental price using supplied evidence",
            Status = PricingAnalysisWorkflowStatus.Completed,
            CurrentStep = 6,
            EvidencePolicyVersion = "pricing-v1",
            EvidenceSufficiency = PricingEvidenceSufficiency.MODERATE,
            Confidence = PricingConfidence.MEDIUM,
            AgentVersion = "pricing-agent-v1",
            ResultJson = "{\"currentSubjectRent\":1250,\"evidenceSufficiency\":\"MODERATE\",\"confidence\":\"MEDIUM\",\"sourceCounts\":{\"listingAskingRent\":1},\"recommendedMinRent\":1200,\"recommendedMaxRent\":1400,\"recommendedRent\":1300,\"evidenceRefs\":[\"cmp-001\"],\"rationaleSummary\":\"Comparable evidence supports this range.\",\"limitations\":[],\"warnings\":[],\"validationPassed\":true,\"advisoryOnly\":true}",
            StartedAt = DateTimeOffset.UtcNow.AddMinutes(-1),
            CompletedAt = DateTimeOffset.UtcNow
        };

        context.PricingAnalysisWorkflows.Add(workflow);
        await context.SaveChangesAsync();

        var stored = await context.PricingAnalysisWorkflows
            .Include(item => item.Property)
            .SingleAsync();

        Assert.Equal(property.Id, stored.PropertyId);
        Assert.Equal(property.Id, stored.Property.Id);
        Assert.Equal(PricingAnalysisWorkflowStatus.Completed, stored.Status);
        Assert.Equal(PricingEvidenceSufficiency.MODERATE, stored.EvidenceSufficiency);
        Assert.Equal(PricingConfidence.MEDIUM, stored.Confidence);
        Assert.Contains("\"advisoryOnly\":true", stored.ResultJson);
        Assert.Null(stored.ErrorMessage);
    }

    [Fact]
    public async Task PersistsSixOrderedStepsIncludingSkippedAnalysisStep()
    {
        await using var context = CreateContext();
        var property = CreateProperty();
        context.Properties.Add(property);
        await context.SaveChangesAsync();

        var workflow = new PricingAnalysisWorkflow
        {
            PropertyId = property.Id,
            Objective = "Assess supplied evidence",
            EvidenceSufficiency = PricingEvidenceSufficiency.INSUFFICIENT,
            Steps = StepNames.Select((name, index) => new PricingAnalysisWorkflowStep
            {
                StepName = name,
                StepOrder = index + 1,
                Status = index == 3
                    ? PricingAnalysisWorkflowStepStatus.Skipped
                    : PricingAnalysisWorkflowStepStatus.Completed,
                OutputSummary = $"Completed {name}.",
                ResultJson = index == 5 ? "{\"evidenceSufficiency\":\"INSUFFICIENT\"}" : null
            }).ToList()
        };

        context.PricingAnalysisWorkflows.Add(workflow);
        await context.SaveChangesAsync();

        var stored = await context.PricingAnalysisWorkflows
            .Include(item => item.Steps)
            .SingleAsync();

        Assert.Equal(StepNames, stored.Steps.OrderBy(step => step.StepOrder).Select(step => step.StepName));
        Assert.Equal(Enumerable.Range(1, 6), stored.Steps.OrderBy(step => step.StepOrder).Select(step => step.StepOrder));
        Assert.Equal(PricingAnalysisWorkflowStepStatus.Skipped, stored.Steps.Single(step => step.StepOrder == 4).Status);
    }

    [Fact]
    public async Task FailedWorkflowPersistsSanitizedErrorAndAllowsSameOrderAcrossWorkflows()
    {
        await using var context = CreateContext();
        var property = CreateProperty();
        context.Properties.Add(property);
        await context.SaveChangesAsync();

        var safeError = "Pricing analysis failed during response validation.";
        var workflows = new[]
        {
            new PricingAnalysisWorkflow
            {
                PropertyId = property.Id,
                Objective = "Assess supplied evidence",
                Status = PricingAnalysisWorkflowStatus.Failed,
                ErrorMessage = safeError,
                Steps = [new PricingAnalysisWorkflowStep { StepName = "plan", StepOrder = 1 }]
            },
            new PricingAnalysisWorkflow
            {
                PropertyId = property.Id,
                Objective = "Assess supplied evidence again",
                Steps = [new PricingAnalysisWorkflowStep { StepName = "plan", StepOrder = 1 }]
            }
        };

        context.PricingAnalysisWorkflows.AddRange(workflows);
        await context.SaveChangesAsync();

        var failed = await context.PricingAnalysisWorkflows.SingleAsync(item => item.Status == PricingAnalysisWorkflowStatus.Failed);
        Assert.Equal(safeError, failed.ErrorMessage);
        Assert.DoesNotContain("token", failed.ErrorMessage, StringComparison.OrdinalIgnoreCase);
        Assert.Equal(2, await context.PricingAnalysisWorkflowSteps.CountAsync(step => step.StepOrder == 1));
    }

    [Fact]
    public void ModelDefinesUniqueOrderedStepsAndRestrictiveRelationshipsWithoutApprovalOrPromptFields()
    {
        using var context = CreateContext();
        var model = context.GetService<IDesignTimeModel>().Model;
        var workflowType = model.FindEntityType(typeof(PricingAnalysisWorkflow))!;
        var stepType = model.FindEntityType(typeof(PricingAnalysisWorkflowStep))!;
        var stepOrderIndex = Assert.Single(stepType.GetIndexes(), index =>
            index.Properties.Select(property => property.Name).SequenceEqual([nameof(PricingAnalysisWorkflowStep.WorkflowId), nameof(PricingAnalysisWorkflowStep.StepOrder)]));

        Assert.True(stepOrderIndex.IsUnique);
        Assert.Contains(workflowType.GetCheckConstraints(), constraint => constraint.Name == "CK_PricingAnalysisWorkflows_CurrentStep");
        Assert.Contains(stepType.GetCheckConstraints(), constraint => constraint.Name == "CK_PricingAnalysisWorkflowSteps_StepOrder");
        Assert.Equal(DeleteBehavior.Restrict, Assert.Single(workflowType.GetForeignKeys()).DeleteBehavior);
        Assert.Equal(DeleteBehavior.Restrict, Assert.Single(stepType.GetForeignKeys()).DeleteBehavior);
        Assert.Equal(
            ["Pending", "Running", "Completed", "Failed"],
            Enum.GetNames<PricingAnalysisWorkflowStatus>());
        Assert.DoesNotContain("AwaitingHumanReview", Enum.GetNames<PricingAnalysisWorkflowStatus>());
        Assert.DoesNotContain("RequiresHumanApproval", typeof(PricingAnalysisWorkflow).GetProperties().Select(property => property.Name));
        Assert.DoesNotContain("ApprovalStatus", typeof(PricingAnalysisWorkflow).GetProperties().Select(property => property.Name));
        Assert.DoesNotContain(typeof(PricingAnalysisWorkflow).GetProperties(), property =>
            property.Name.Contains("Prompt", StringComparison.OrdinalIgnoreCase));
        Assert.DoesNotContain(typeof(PricingAnalysisWorkflow).GetProperties(), property =>
            property.Name.Contains("Reasoning", StringComparison.OrdinalIgnoreCase));
    }

    private static Property CreateProperty() => new()
    {
        LandlordId = Guid.NewGuid(),
        Title = "Two bedroom apartment",
        Description = "A property for persistence testing.",
        Address = "1 Test Road",
        City = "Colombo",
        MonthlyRent = 1250m,
        Bedrooms = 2,
        Bathrooms = 1
    };

    private static ApplicationDbContext CreateContext() => new(new DbContextOptionsBuilder<ApplicationDbContext>()
        .UseInMemoryDatabase($"PricingAnalysisWorkflow-{Guid.NewGuid()}")
        .Options);
}
