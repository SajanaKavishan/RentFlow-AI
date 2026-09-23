using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;
using RentFlow.Api.Data;
using RentFlow.Api.DTOs.Maintenance;
using RentFlow.Api.Models;
using RentFlow.Api.Services;
using RentFlow.Api.Services.Interfaces;
using Xunit;

namespace RentFlow.Api.Tests.Services;

public class MaintenanceCoordinationOrchestratorTests
{
    [Fact]
    public async Task StartAnalysisAsync_CreatesWorkflowAndPersistsSteps()
    {
        await using var context = CreateContext();
        var request = CreateRequest();
        context.MaintenanceRequests.Add(request);
        await context.SaveChangesAsync();

        var orchestrator = CreateOrchestrator(context, new FakeAgentClient());
        var workflow = await orchestrator.StartAnalysisAsync(request.Id);

        Assert.Equal(MaintenanceCoordinationWorkflowStatus.AwaitingHumanReview, workflow.Status);
        Assert.Equal(request.Id, workflow.MaintenanceRequestId);
        Assert.Equal("Review the maintenance request and recommend a safe advisory action without approving or changing status.", workflow.Objective);
        Assert.Equal(3, workflow.Steps.Count);
        Assert.Equal([1, 2, 3], workflow.Steps.OrderBy(step => step.StepOrder).Select(step => step.StepOrder).ToArray());
        Assert.Equal(
            ["Maintenance data validation", "Maintenance coordination rules", "Maintenance coordination agent"],
            workflow.Steps.OrderBy(step => step.StepOrder).Select(step => step.StepName).ToArray());
        Assert.All(workflow.Steps, step => Assert.Equal(MaintenanceCoordinationStepStatus.Completed, step.Status));

        var stored = await context.MaintenanceCoordinationWorkflows
            .Include(item => item.Steps)
            .SingleAsync();
        Assert.Equal(workflow.Id, stored.Id);
        Assert.Equal(3, stored.Steps.Count);
        Assert.Equal("plumbing", JsonDocument.Parse(stored.FinalResultJson!).RootElement.GetProperty("recommendedCategory").GetString());
    }

    [Fact]
    public async Task StartAnalysisAsync_ExecutesDeterministicToolsBeforeAgent()
    {
        await using var context = CreateContext();
        var request = CreateRequest();
        context.MaintenanceRequests.Add(request);
        await context.SaveChangesAsync();

        var agent = new FakeAgentClient();
        var validationTool = new FakeValidationTool();
        var ruleTool = new FakeRuleTool();
        var orchestrator = CreateOrchestrator(context, agent, validationTool, ruleTool);
        await orchestrator.StartAnalysisAsync(request.Id);

        Assert.Equal(
            [
                "MaintenanceRequestDataValidationTool",
                "MaintenanceCoordinationRuleTool",
                "MaintenanceCoordinationAgentClient"
            ],
            validationTool.CallOrder.Concat(ruleTool.CallOrder).Concat(agent.CallOrder).ToArray());
    }

    [Fact]
    public async Task StartAnalysisAsync_PersistsToolAndAgentResults()
    {
        await using var context = CreateContext();
        var request = CreateRequest();
        context.MaintenanceRequests.Add(request);
        await context.SaveChangesAsync();

        var agent = new FakeAgentClient();
        var orchestrator = CreateOrchestrator(context, agent);
        var workflow = await orchestrator.StartAnalysisAsync(request.Id);

        var stepOne = workflow.Steps.Single(step => step.StepOrder == 1);
        var stepTwo = workflow.Steps.Single(step => step.StepOrder == 2);
        var stepThree = workflow.Steps.Single(step => step.StepOrder == 3);

        Assert.NotNull(stepOne.OutputSummary);
        Assert.NotNull(stepTwo.OutputSummary);
        Assert.NotNull(stepThree.OutputSummary);
        Assert.NotNull(stepOne.ValidationSummary);
        Assert.NotNull(stepTwo.ValidationSummary);
        Assert.NotNull(stepThree.ValidationSummary);
        Assert.NotNull(workflow.FinalResultJson);
        Assert.Contains("recommendedCategory", workflow.FinalResultJson);
    }

    [Fact]
    public async Task StartAnalysisAsync_PersistsExecutionOrder()
    {
        await using var context = CreateContext();
        var request = CreateRequest();
        context.MaintenanceRequests.Add(request);
        await context.SaveChangesAsync();

        var orchestrator = CreateOrchestrator(context, new FakeAgentClient());
        var workflow = await orchestrator.StartAnalysisAsync(request.Id);

        Assert.Equal([1, 2, 3], workflow.Steps.OrderBy(step => step.StepOrder).Select(step => step.StepOrder).ToArray());
        Assert.Equal(
            ["Maintenance data validation", "Maintenance coordination rules", "Maintenance coordination agent"],
            workflow.Steps.OrderBy(step => step.StepOrder).Select(step => step.StepName).ToArray());
    }

    [Fact]
    public async Task StartAnalysisAsync_FailedAgentResponse_SafelyFailsWorkflow()
    {
        await using var context = CreateContext();
        var request = CreateRequest();
        context.MaintenanceRequests.Add(request);
        await context.SaveChangesAsync();

        var orchestrator = CreateOrchestrator(context, new FakeAgentClient { ThrowOnAnalyze = true });
        var workflow = await orchestrator.StartAnalysisAsync(request.Id);

        Assert.Equal(MaintenanceCoordinationWorkflowStatus.Failed, workflow.Status);
        Assert.Equal(MaintenanceCoordinationApprovalStatus.Pending, workflow.ApprovalStatus);
        Assert.Equal("The maintenance coordination step failed unexpectedly.", workflow.ErrorMessage);
        Assert.Equal(MaintenanceRequestStatus.Submitted, await context.MaintenanceRequests.Select(item => item.Status).SingleAsync());
    }

    [Fact]
    public async Task StartAnalysisAsync_SuccessfulWorkflowStopsAtAwaitingHumanReview()
    {
        await using var context = CreateContext();
        var request = CreateRequest();
        context.MaintenanceRequests.Add(request);
        await context.SaveChangesAsync();

        var agent = new FakeAgentClient();
        var orchestrator = CreateOrchestrator(context, agent);
        var workflow = await orchestrator.StartAnalysisAsync(request.Id);

        Assert.Equal(MaintenanceCoordinationWorkflowStatus.AwaitingHumanReview, workflow.Status);
        Assert.Equal(MaintenanceCoordinationApprovalStatus.Pending, workflow.ApprovalStatus);
        Assert.Equal(MaintenanceRequestStatus.Submitted, request.Status);
        Assert.NotNull(workflow.FinalResultJson);
        Assert.Contains("Schedule technician review", workflow.FinalResultJson);
        Assert.DoesNotContain("Approved", workflow.FinalResultJson, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("Rejected", workflow.FinalResultJson, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task ApproveAsync_TransitionsWorkflowToApproved()
    {
        await using var context = CreateContext();
        var request = CreateRequest();
        context.MaintenanceRequests.Add(request);
        await context.SaveChangesAsync();

        var orchestrator = CreateOrchestrator(context, new FakeAgentClient());
        var workflow = await orchestrator.StartAnalysisAsync(request.Id);

        var approved = await orchestrator.ApproveAsync(workflow.Id, Guid.NewGuid(), "Approved after landlord review.");

        Assert.Equal(MaintenanceCoordinationWorkflowStatus.Completed, approved.Status);
        Assert.Equal(MaintenanceCoordinationApprovalStatus.Approved, approved.ApprovalStatus);
        Assert.Equal("Approved after landlord review.", JsonDocument.Parse(approved.FinalResultJson!).RootElement.GetProperty("decisionDetails").GetProperty("decisionNotes").GetString());
    }

    [Fact]
    public async Task RejectAsync_TransitionsWorkflowToRejected()
    {
        await using var context = CreateContext();
        var request = CreateRequest();
        context.MaintenanceRequests.Add(request);
        await context.SaveChangesAsync();

        var orchestrator = CreateOrchestrator(context, new FakeAgentClient());
        var workflow = await orchestrator.StartAnalysisAsync(request.Id);

        var rejected = await orchestrator.RejectAsync(workflow.Id, Guid.NewGuid(), "Request additional evidence.");

        Assert.Equal(MaintenanceCoordinationWorkflowStatus.Failed, rejected.Status);
        Assert.Equal(MaintenanceCoordinationApprovalStatus.Rejected, rejected.ApprovalStatus);
        Assert.Equal("Request additional evidence.", JsonDocument.Parse(rejected.FinalResultJson!).RootElement.GetProperty("decisionDetails").GetProperty("decisionNotes").GetString());
    }

    private static ApplicationDbContext CreateContext() => new(new DbContextOptionsBuilder<ApplicationDbContext>()
        .UseInMemoryDatabase($"MaintenanceCoordinationOrchestrator-{Guid.NewGuid()}")
        .Options);

    private static MaintenanceRequest CreateRequest() => new()
    {
        Title = "Leaking sink",
        Description = "Water is leaking under the sink.",
        Category = MaintenanceCategory.Plumbing,
        Priority = MaintenancePriority.High,
        Status = MaintenanceRequestStatus.Submitted,
        TechnicianId = Guid.NewGuid(),
        PropertyId = Guid.NewGuid(),
        TenantId = Guid.NewGuid()
    };

    private static MaintenanceCoordinationOrchestrator CreateOrchestrator(
        ApplicationDbContext context,
        IMaintenanceCoordinationAgentClient? agentClient = null,
        IMaintenanceRequestDataValidationTool? validationTool = null,
        IMaintenanceCoordinationRuleTool? ruleTool = null)
    {
        agentClient ??= new FakeAgentClient();
        validationTool ??= new FakeValidationTool();
        ruleTool ??= new FakeRuleTool();

        return new MaintenanceCoordinationOrchestrator(
            context,
            validationTool,
            ruleTool,
            agentClient,
            TimeProvider.System,
            NullLogger<MaintenanceCoordinationOrchestrator>.Instance);
    }

    private sealed class FakeValidationTool : IMaintenanceRequestDataValidationTool
    {
        public List<string> CallOrder { get; } = [];

        public Task<MaintenanceDataValidationResult> ValidateAsync(MaintenanceRequest? request, CancellationToken cancellationToken = default)
        {
            CallOrder.Add("MaintenanceRequestDataValidationTool");
            return Task.FromResult(new MaintenanceDataValidationResult
            {
                IsValid = true,
                CompletenessScore = 100m,
                MissingFields = [],
                Warnings = []
            });
        }
    }

    private sealed class FakeRuleTool : IMaintenanceCoordinationRuleTool
    {
        public List<string> CallOrder { get; } = [];

        public Task<MaintenanceCoordinationRuleValidationResult> ValidateAsync(
            MaintenanceRequest? request,
            RepairEstimate? estimate = null,
            CancellationToken cancellationToken = default)
        {
            CallOrder.Add("MaintenanceCoordinationRuleTool");
            return Task.FromResult(new MaintenanceCoordinationRuleValidationResult
            {
                Passed = true,
                PassedRules = ["MaintenanceRequestExists", "MaintenanceCategoryIsDefined", "MaintenancePriorityIsDefined", "MaintenanceDescriptionIsPresent"],
                FailedRules = [],
                Warnings = []
            });
        }
    }

    private sealed class FakeAgentClient : IMaintenanceCoordinationAgentClient
    {
        public List<string> CallOrder { get; } = [];
        public bool ThrowOnAnalyze { get; init; }

        public Task<MaintenanceCoordinationAgentResponse> AnalyzeAsync(MaintenanceCoordinationAgentRequest request, CancellationToken cancellationToken = default)
        {
            CallOrder.Add("MaintenanceCoordinationAgentClient");
            if (ThrowOnAnalyze)
            {
                throw new MaintenanceCoordinationAgentClientException(MaintenanceCoordinationAgentClientError.ServiceUnavailable, "down");
            }

            return Task.FromResult(new MaintenanceCoordinationAgentResponse
            {
                MaintenanceRequestId = request.MaintenanceRequestId,
                Result = new MaintenanceCoordinationResult
                {
                    RecommendedCategory = "plumbing",
                    RecommendedPriority = "high",
                    NextAction = "Schedule technician review",
                    Reasoning = "The leak should be reviewed by a technician.",
                    Warnings = ["No estimate was supplied."],
                    AgentVersion = "test-agent-1.0"
                },
                ExecutionMetadata = new MaintenanceCoordinationExecutionMetadata
                {
                    ExecutedSteps = ["plan", "classify_assess_issue", "assess_urgency", "review_maintenance_information", "produce_coordination_recommendation", "summarize"]
                }
            });
        }
    }
}
