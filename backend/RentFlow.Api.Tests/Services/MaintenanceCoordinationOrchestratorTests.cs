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
        Assert.Equal("Plumbing", JsonDocument.Parse(stored.FinalResultJson!).RootElement.GetProperty("suggestedCategory").GetString());
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
        Assert.Contains("suggestedCategory", workflow.FinalResultJson);
    }

    [Fact]
    public async Task StartAnalysisAsync_SendsSafeMetadataAndEstimateInCanonicalContractShape()
    {
        await using var context = CreateContext();
        var request = CreateRequest();
        var attachmentId = Guid.NewGuid();
        context.MaintenanceRequests.Add(request);
        context.MaintenanceAttachments.Add(new MaintenanceAttachment
        {
            Id = attachmentId,
            MaintenanceRequestId = request.Id,
            StorageKey = "private/not-forwarded",
            FileName = "leak.jpg",
            ContentType = "image/jpeg",
            FileSize = 1234,
            AttachmentType = "damage photo",
            UploadedByUserId = Guid.NewGuid()
        });
        context.RepairEstimates.Add(new RepairEstimate
        {
            MaintenanceRequestId = request.Id,
            TechnicianId = request.TechnicianId!.Value,
            VersionNumber = 1,
            TotalCost = 250m,
            Status = RepairEstimateStatus.Submitted
        });
        await context.SaveChangesAsync();

        var agent = new FakeAgentClient();
        await CreateOrchestrator(context, agent).StartAnalysisAsync(request.Id);

        var agentRequest = Assert.IsType<MaintenanceCoordinationAgentRequest>(agent.Request);
        var attachment = Assert.Single(agentRequest.Attachments);
        Assert.Equal(attachmentId, attachment.AttachmentId);
        Assert.True(attachment.FileSize > 0);
        Assert.Equal("image/jpeg", attachment.ContentType);
        Assert.Equal(250m, agentRequest.RepairEstimate!.TotalCost);

        var payload = JsonSerializer.SerializeToElement(agentRequest, new JsonSerializerOptions(JsonSerializerDefaults.Web));
        Assert.Equal(
            ["maintenanceRequestId", "title", "description", "category", "priority", "currentStatus", "preferredAccessWindow", "hasAssignedTechnician", "repairEstimate", "attachments", "evidencePhotos", "photoLimitations"],
            payload.EnumerateObject().Select(property => property.Name).ToArray());
        Assert.Equal(
            ["attachmentId", "contentType", "fileSize"],
            payload.GetProperty("attachments")[0].EnumerateObject().Select(property => property.Name).ToArray());
        Assert.False(payload.GetProperty("repairEstimate").TryGetProperty("currency", out _));
        Assert.DoesNotContain("storageKey", payload.ToString(), StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task StartAnalysisAsync_SendsEmptyAttachmentCollectionWhenNoneExist()
    {
        await using var context = CreateContext();
        var request = CreateRequest();
        context.MaintenanceRequests.Add(request);
        await context.SaveChangesAsync();

        var agent = new FakeAgentClient();
        await CreateOrchestrator(context, agent).StartAnalysisAsync(request.Id);

        var agentRequest = Assert.IsType<MaintenanceCoordinationAgentRequest>(agent.Request);
        Assert.Empty(agentRequest.Attachments);

        var payload = JsonSerializer.SerializeToElement(agentRequest, new JsonSerializerOptions(JsonSerializerDefaults.Web));
        Assert.Empty(payload.GetProperty("attachments").EnumerateArray());
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
    public async Task StartAnalysisAsync_ValidationFailurePersistsResultsAndSkipsAgent()
    {
        await using var context = CreateContext();
        var request = CreateRequest();
        context.MaintenanceRequests.Add(request);
        await context.SaveChangesAsync();

        var agent = new FakeAgentClient();
        var validationTool = new FakeValidationTool(isValid: false);
        var ruleTool = new FakeRuleTool();
        var orchestrator = CreateOrchestrator(context, agent, validationTool, ruleTool);

        var workflow = await orchestrator.StartAnalysisAsync(request.Id);

        Assert.Equal(MaintenanceCoordinationWorkflowStatus.Failed, workflow.Status);
        Assert.False(workflow.RequiresHumanApproval);
        Assert.Equal(MaintenanceCoordinationApprovalStatus.NotRequired, workflow.ApprovalStatus);
        Assert.Contains("Maintenance data validation failed", workflow.ErrorMessage);
        Assert.Contains("Title", workflow.ErrorMessage);
        Assert.Empty(agent.CallOrder);
        Assert.Single(validationTool.CallOrder);
        Assert.Single(ruleTool.CallOrder);
        Assert.Equal(2, workflow.CurrentStep);
        Assert.Equal(MaintenanceCoordinationStepStatus.Completed, workflow.Steps.Single(step => step.StepOrder == 1).Status);
        Assert.Equal(MaintenanceCoordinationStepStatus.Completed, workflow.Steps.Single(step => step.StepOrder == 2).Status);
        Assert.Equal(MaintenanceCoordinationStepStatus.Pending, workflow.Steps.Single(step => step.StepOrder == 3).Status);
        Assert.Contains("\"isValid\":false", workflow.Steps.Single(step => step.StepOrder == 1).OutputSummary);
        Assert.Contains("\"passed\":true", workflow.Steps.Single(step => step.StepOrder == 2).OutputSummary);
        Assert.Contains("stopped before AI agent execution", workflow.ExecutionSummary);
    }

    [Fact]
    public async Task StartAnalysisAsync_RuleFailurePersistsResultsAndSkipsAgent()
    {
        await using var context = CreateContext();
        var request = CreateRequest();
        context.MaintenanceRequests.Add(request);
        await context.SaveChangesAsync();

        var agent = new FakeAgentClient();
        var validationTool = new FakeValidationTool();
        var ruleTool = new FakeRuleTool(passed: false);
        var orchestrator = CreateOrchestrator(context, agent, validationTool, ruleTool);

        var workflow = await orchestrator.StartAnalysisAsync(request.Id);

        Assert.Equal(MaintenanceCoordinationWorkflowStatus.Failed, workflow.Status);
        Assert.False(workflow.RequiresHumanApproval);
        Assert.Equal(MaintenanceCoordinationApprovalStatus.NotRequired, workflow.ApprovalStatus);
        Assert.Contains("Maintenance coordination rules failed", workflow.ErrorMessage);
        Assert.Contains("MaintenanceDescriptionIsPresent", workflow.ErrorMessage);
        Assert.Empty(agent.CallOrder);
        Assert.Single(validationTool.CallOrder);
        Assert.Single(ruleTool.CallOrder);
        Assert.Equal(2, workflow.CurrentStep);
        Assert.Equal(MaintenanceCoordinationStepStatus.Completed, workflow.Steps.Single(step => step.StepOrder == 1).Status);
        Assert.Equal(MaintenanceCoordinationStepStatus.Completed, workflow.Steps.Single(step => step.StepOrder == 2).Status);
        Assert.Equal(MaintenanceCoordinationStepStatus.Pending, workflow.Steps.Single(step => step.StepOrder == 3).Status);
        Assert.Contains("\"isValid\":true", workflow.Steps.Single(step => step.StepOrder == 1).OutputSummary);
        Assert.Contains("\"passed\":false", workflow.Steps.Single(step => step.StepOrder == 2).OutputSummary);
        Assert.Contains("stopped before AI agent execution", workflow.ExecutionSummary);
    }

    [Fact]
    public async Task StartAnalysisAsync_SuccessfulDeterministicChecksInvokeAgentAndAwaitReview()
    {
        await using var context = CreateContext();
        var request = CreateRequest();
        context.MaintenanceRequests.Add(request);
        await context.SaveChangesAsync();

        var agent = new FakeAgentClient();
        var validationTool = new FakeValidationTool();
        var ruleTool = new FakeRuleTool();
        var orchestrator = CreateOrchestrator(context, agent, validationTool, ruleTool);

        var workflow = await orchestrator.StartAnalysisAsync(request.Id);

        Assert.Equal(MaintenanceCoordinationWorkflowStatus.AwaitingHumanReview, workflow.Status);
        Assert.Equal(MaintenanceCoordinationApprovalStatus.Pending, workflow.ApprovalStatus);
        Assert.Single(agent.CallOrder);
        Assert.Single(validationTool.CallOrder);
        Assert.Single(ruleTool.CallOrder);
        Assert.All(workflow.Steps, step => Assert.Equal(MaintenanceCoordinationStepStatus.Completed, step.Status));
        Assert.NotNull(workflow.FinalResultJson);
        Assert.Contains("triage", workflow.FinalResultJson);
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
        Assert.Equal(MaintenanceCoordinationApprovalStatus.NotRequired, workflow.ApprovalStatus);
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
        Assert.Contains("triage", workflow.FinalResultJson);
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

    [Theory]
    [InlineData(true)]
    [InlineData(false)]
    public async Task Abort_CleansRunningAnalysisWithoutChangingMaintenance(bool callerCancelled)
    {
        await using var context = CreateContext();
        var request = CreateRequest();
        context.MaintenanceRequests.Add(request);
        await context.SaveChangesAsync();
        using var source = new CancellationTokenSource();
        var agent = new CancellingAgent(callerCancelled ? source : null);
        var orchestrator = new MaintenanceCoordinationOrchestrator(context, new MaintenanceRequestDataValidationTool(),
            new MaintenanceCoordinationRuleTool(), agent, TimeProvider.System,
            NullLogger<MaintenanceCoordinationOrchestrator>.Instance,
            Microsoft.Extensions.Options.Options.Create(new RentFlow.Api.Configuration.AgentServiceOptions { TimeoutSeconds = 1 }));
        if (callerCancelled)
            await Assert.ThrowsAnyAsync<OperationCanceledException>(() => orchestrator.StartAnalysisAsync(request.Id, source.Token));
        else
            Assert.Equal(MaintenanceCoordinationWorkflowStatus.Failed, (await orchestrator.StartAnalysisAsync(request.Id)).Status);
        var stored = await context.MaintenanceCoordinationWorkflows.Include(item => item.Steps).SingleAsync();
        Assert.Equal(MaintenanceCoordinationWorkflowStatus.Failed, stored.Status);
        Assert.Equal(MaintenanceCoordinationApprovalStatus.NotRequired, stored.ApprovalStatus);
        Assert.DoesNotContain(stored.Steps, step => step.Status == MaintenanceCoordinationStepStatus.Running);
        Assert.Null(stored.FinalResultJson);
        Assert.Equal(MaintenanceRequestStatus.Submitted, request.Status);
        Assert.Equal(MaintenanceCategory.Plumbing, request.Category);
        Assert.Equal(MaintenancePriority.High, request.Priority);
    }

    [Fact]
    public async Task FailedAnalysis_DoesNotPreventHumanTriage()
    {
        await using var context = CreateContext();
        var request = CreateRequest();
        context.MaintenanceRequests.Add(request);
        await context.SaveChangesAsync();
        var workflow = await CreateOrchestrator(context, new FakeAgentClient { ThrowOnAnalyze = true }).StartAnalysisAsync(request.Id);
        Assert.Equal(MaintenanceCoordinationWorkflowStatus.Failed, workflow.Status);
        var triaged = await new MaintenanceRequestService(context).TriageAsync(request.Id, new TriageMaintenanceRequestDto
            { Category = MaintenanceCategory.Plumbing, Priority = MaintenancePriority.High });
        Assert.Equal(MaintenanceRequestStatus.Triaged, triaged.Status);
    }

    private sealed class CancellingAgent(CancellationTokenSource? source) : IMaintenanceCoordinationAgentClient
    {
        public async Task<MaintenanceCoordinationAgentResponse> AnalyzeAsync(MaintenanceCoordinationAgentRequest request, CancellationToken cancellationToken = default)
        {
            source?.Cancel();
            await Task.Delay(Timeout.Infinite, cancellationToken);
            throw new InvalidOperationException();
        }
    }

    [Fact]
    public async Task TotalDeadline_IncludesMediaPreparationAndKeepsBusinessStateIntact()
    {
        await using var context = CreateContext();
        var request = CreateRequest();
        var originalTechnician = request.TechnicianId;
        context.MaintenanceRequests.Add(request);
        await context.SaveChangesAsync();
        var agent = new FakeAgentClient();
        var orchestrator = new MaintenanceCoordinationOrchestrator(context, new FakeValidationTool(), new FakeRuleTool(),
            agent, TimeProvider.System, NullLogger<MaintenanceCoordinationOrchestrator>.Instance,
            Microsoft.Extensions.Options.Options.Create(new RentFlow.Api.Configuration.AgentServiceOptions { TimeoutSeconds = 1 }),
            new SlowPhotoEvidence());
        var workflow = await orchestrator.StartAnalysisAsync(request.Id);
        Assert.Equal(MaintenanceCoordinationWorkflowStatus.Failed, workflow.Status);
        Assert.Equal(MaintenanceCoordinationStepStatus.Failed, workflow.Steps.Single(step => step.StepOrder == 3).Status);
        Assert.Null(workflow.FinalResultJson);
        Assert.Empty(agent.CallOrder);
        Assert.Equal(originalTechnician, request.TechnicianId);
        Assert.Equal(MaintenanceRequestStatus.Submitted, request.Status);
        Assert.Equal(MaintenanceCategory.Plumbing, request.Category);
        Assert.Equal(MaintenancePriority.High, request.Priority);
        Assert.Empty(context.MaintenanceStatusHistories);
    }

    private sealed class SlowPhotoEvidence : IMaintenancePhotoEvidenceService
    {
        public Task PrepareAsync(MaintenanceRequest request, IReadOnlyCollection<MaintenanceAttachment> attachments,
            MaintenanceCoordinationAgentRequest payload, CancellationToken token) => Task.Delay(Timeout.Infinite, token);
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
        public FakeValidationTool(bool isValid = true)
        {
            IsValid = isValid;
        }

        public List<string> CallOrder { get; } = [];
        private bool IsValid { get; }

        public Task<MaintenanceDataValidationResult> ValidateAsync(MaintenanceRequest? request, CancellationToken cancellationToken = default)
        {
            CallOrder.Add("MaintenanceRequestDataValidationTool");
            return Task.FromResult(new MaintenanceDataValidationResult
            {
                IsValid = IsValid,
                CompletenessScore = IsValid ? 100m : 85.71m,
                MissingFields = IsValid ? [] : ["Title"],
                Warnings = IsValid ? [] : ["A title is required."]
            });
        }
    }

    private sealed class FakeRuleTool : IMaintenanceCoordinationRuleTool
    {
        public FakeRuleTool(bool passed = true)
        {
            Passed = passed;
        }

        public List<string> CallOrder { get; } = [];
        private bool Passed { get; }

        public Task<MaintenanceCoordinationRuleValidationResult> ValidateAsync(
            MaintenanceRequest? request,
            RepairEstimate? estimate = null,
            CancellationToken cancellationToken = default)
        {
            CallOrder.Add("MaintenanceCoordinationRuleTool");
            return Task.FromResult(new MaintenanceCoordinationRuleValidationResult
            {
                Passed = Passed,
                PassedRules = Passed
                    ? ["MaintenanceRequestExists", "MaintenanceCategoryIsDefined", "MaintenancePriorityIsDefined", "MaintenanceDescriptionIsPresent"]
                    : ["MaintenanceRequestExists", "MaintenanceCategoryIsDefined", "MaintenancePriorityIsDefined"],
                FailedRules = Passed ? [] : ["MaintenanceDescriptionIsPresent"],
                Warnings = Passed ? [] : ["A maintenance description is required."]
            });
        }
    }

    private sealed class FakeAgentClient : IMaintenanceCoordinationAgentClient
    {
        public List<string> CallOrder { get; } = [];
        public bool ThrowOnAnalyze { get; init; }
        public MaintenanceCoordinationAgentRequest? Request { get; private set; }

        public Task<MaintenanceCoordinationAgentResponse> AnalyzeAsync(MaintenanceCoordinationAgentRequest request, CancellationToken cancellationToken = default)
        {
            CallOrder.Add("MaintenanceCoordinationAgentClient");
            Request = request;
            if (ThrowOnAnalyze)
            {
                throw new MaintenanceCoordinationAgentClientException(MaintenanceCoordinationAgentClientError.ServiceUnavailable, "down");
            }

            return Task.FromResult(new MaintenanceCoordinationAgentResponse
            {
                MaintenanceRequestId = request.MaintenanceRequestId,
                Result = MaintenanceCoordinationTestData.Result(request),
                ExecutionMetadata = new MaintenanceCoordinationExecutionMetadata
                {
                    ExecutedSteps = ["plan", "classify_assess_issue", "assess_urgency", "review_maintenance_information", "produce_coordination_recommendation", "summarize"]
                }
            });
        }
    }
}
