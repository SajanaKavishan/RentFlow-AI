using Microsoft.EntityFrameworkCore;
using RentFlow.Api.Data;
using RentFlow.Api.Models;
using Xunit;

namespace RentFlow.Api.Tests.Services;

public class MaintenanceCoordinationWorkflowPersistenceTests
{
    [Fact]
    public async Task CanPersistWorkflowAndOrderedSteps()
    {
        await using var context = CreateContext();
        var request = new MaintenanceRequest
        {
            PropertyId = Guid.NewGuid(),
            TenantId = Guid.NewGuid(),
            Title = "Leaking tap",
            Description = "Water is leaking from the kitchen sink.",
            Category = MaintenanceCategory.Plumbing,
            Priority = MaintenancePriority.High,
            Status = MaintenanceRequestStatus.Submitted
        };
        context.MaintenanceRequests.Add(request);
        await context.SaveChangesAsync();

        var workflow = new MaintenanceCoordinationWorkflow
        {
            MaintenanceRequestId = request.Id,
            Objective = "Assess maintenance coordination recommendation",
            Status = MaintenanceCoordinationWorkflowStatus.AwaitingHumanReview,
            CurrentStep = 2,
            AgentVersion = "maintenance-agent-1.0",
            PlanSummary = "plan -> assess -> recommend",
            ExecutionSummary = "Completed all workflow steps",
            FinalResultJson = "{\"recommendedCategory\":\"plumbing\",\"recommendedPriority\":\"high\"}",
            ErrorMessage = null,
            RequiresHumanApproval = true,
            ApprovalStatus = MaintenanceCoordinationApprovalStatus.Pending,
            Steps =
            [
                new MaintenanceCoordinationStep
                {
                    StepName = "plan",
                    StepOrder = 1,
                    Status = MaintenanceCoordinationStepStatus.Completed,
                    InputSummary = "maintenance request",
                    OutputSummary = "planned issue assessment",
                    ValidationSummary = "passed",
                    StartedAt = DateTimeOffset.UtcNow.AddMinutes(-2),
                    CompletedAt = DateTimeOffset.UtcNow.AddMinutes(-1)
                },
                new MaintenanceCoordinationStep
                {
                    StepName = "recommendation",
                    StepOrder = 2,
                    Status = MaintenanceCoordinationStepStatus.Running,
                    InputSummary = "assessment data",
                    OutputSummary = "coordination recommendation pending",
                    ValidationSummary = "in progress",
                    StartedAt = DateTimeOffset.UtcNow.AddMinutes(-1)
                }
            ]
        };

        context.MaintenanceCoordinationWorkflows.Add(workflow);
        await context.SaveChangesAsync();

        var stored = await context.MaintenanceCoordinationWorkflows
            .Include(w => w.Steps)
            .SingleAsync();

        Assert.Equal(request.Id, stored.MaintenanceRequestId);
        Assert.Equal("Assess maintenance coordination recommendation", stored.Objective);
        Assert.Equal(MaintenanceCoordinationWorkflowStatus.AwaitingHumanReview, stored.Status);
        Assert.Equal("maintenance-agent-1.0", stored.AgentVersion);
        Assert.Equal("{\"recommendedCategory\":\"plumbing\",\"recommendedPriority\":\"high\"}", stored.FinalResultJson);
        Assert.Equal(2, stored.Steps.Count);
        Assert.Equal([1, 2], stored.Steps.Select(step => step.StepOrder).OrderBy(x => x).ToArray());
        Assert.Contains(stored.Steps, step => step.StepName == "recommendation" && step.Status == MaintenanceCoordinationStepStatus.Running);
        Assert.Equal(stored.CreatedAt, stored.CreatedAt);
        Assert.Equal(stored.UpdatedAt, stored.UpdatedAt);
    }

    [Fact]
    public async Task StoresSafeFailureMetadataWithoutSensitiveDetails()
    {
        await using var context = CreateContext();
        var request = new MaintenanceRequest
        {
            PropertyId = Guid.NewGuid(),
            TenantId = Guid.NewGuid(),
            Title = "Unknown issue",
            Description = "Needs assessment.",
            Category = MaintenanceCategory.Other,
            Priority = MaintenancePriority.Normal,
            Status = MaintenanceRequestStatus.Submitted
        };
        context.MaintenanceRequests.Add(request);
        await context.SaveChangesAsync();

        var workflow = new MaintenanceCoordinationWorkflow
        {
            MaintenanceRequestId = request.Id,
            Objective = "Assess issue",
            Status = MaintenanceCoordinationWorkflowStatus.Failed,
            CurrentStep = 3,
            AgentVersion = "maintenance-agent-1.0",
            FinalResultJson = "{\"status\":\"failed\"}",
            ErrorMessage = "The maintenance coordination step failed unexpectedly.",
            RequiresHumanApproval = true,
            ApprovalStatus = MaintenanceCoordinationApprovalStatus.Pending,
            Steps =
            [
                new MaintenanceCoordinationStep
                {
                    StepName = "classify_assess_issue",
                    StepOrder = 1,
                    Status = MaintenanceCoordinationStepStatus.Completed,
                    OutputSummary = "issue classified",
                    ValidationSummary = "ok"
                },
                new MaintenanceCoordinationStep
                {
                    StepName = "summarize",
                    StepOrder = 2,
                    Status = MaintenanceCoordinationStepStatus.Failed,
                    ErrorMessage = "Provider timed out and no raw secret data was stored.",
                    ValidationSummary = "failed validation"
                }
            ]
        };

        context.MaintenanceCoordinationWorkflows.Add(workflow);
        await context.SaveChangesAsync();

        var stored = await context.MaintenanceCoordinationWorkflows
            .Include(w => w.Steps)
            .SingleAsync();

        Assert.Equal(MaintenanceCoordinationWorkflowStatus.Failed, stored.Status);
        Assert.True(stored.RequiresHumanApproval);
        Assert.Equal(MaintenanceCoordinationApprovalStatus.Pending, stored.ApprovalStatus);
        Assert.Equal("The maintenance coordination step failed unexpectedly.", stored.ErrorMessage);
        Assert.DoesNotContain("token", stored.ErrorMessage, StringComparison.OrdinalIgnoreCase);
        Assert.Contains(stored.Steps, step => step.StepName == "summarize" && step.ErrorMessage != null);
        Assert.DoesNotContain("secret", stored.ErrorMessage ?? string.Empty, StringComparison.OrdinalIgnoreCase);
    }

    private static ApplicationDbContext CreateContext() => new(new DbContextOptionsBuilder<ApplicationDbContext>()
        .UseInMemoryDatabase($"MaintenanceCoordinationWorkflow-{Guid.NewGuid()}")
        .Options);
}
