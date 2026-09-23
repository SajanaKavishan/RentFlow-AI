using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using RentFlow.Api.Data;
using RentFlow.Api.DTOs.Maintenance;
using RentFlow.Api.Models;
using RentFlow.Api.Services.Interfaces;

namespace RentFlow.Api.Services;

/// <summary>
/// Executes the deterministic maintenance coordination checks first, then invokes the
/// advisory maintenance agent and persists the workflow state without changing authoritative status.
/// </summary>
public sealed class MaintenanceCoordinationOrchestrator(
    ApplicationDbContext dbContext,
    IMaintenanceRequestDataValidationTool maintenanceRequestDataValidationTool,
    IMaintenanceCoordinationRuleTool maintenanceCoordinationRuleTool,
    IMaintenanceCoordinationAgentClient maintenanceCoordinationAgentClient,
    TimeProvider timeProvider,
    ILogger<MaintenanceCoordinationOrchestrator> logger) : IMaintenanceCoordinationOrchestrator
{
    private const string WorkflowObjective = "Review the maintenance request and recommend a safe advisory action without approving or changing status.";
    private const string SafeStepErrorMessage = "The maintenance coordination step failed unexpectedly.";

    public Task<MaintenanceCoordinationWorkflow> StartAsync(
        Guid maintenanceRequestId,
        CancellationToken cancellationToken = default)
        => StartAnalysisAsync(maintenanceRequestId, cancellationToken);

    public async Task<MaintenanceCoordinationWorkflow> StartAnalysisAsync(
        Guid maintenanceRequestId,
        CancellationToken cancellationToken = default)
    {
        if (maintenanceRequestId == Guid.Empty)
        {
            throw MaintenanceRequestServiceException.Validation("A maintenance request ID is required.");
        }

        var request = await dbContext.MaintenanceRequests
            .SingleOrDefaultAsync(item => item.Id == maintenanceRequestId, cancellationToken)
            ?? throw MaintenanceRequestServiceException.NotFound($"Maintenance request '{maintenanceRequestId}' was not found.");

        var estimate = await dbContext.RepairEstimates
            .AsNoTracking()
            .Where(item => item.MaintenanceRequestId == maintenanceRequestId)
            .OrderByDescending(item => item.VersionNumber)
            .ThenByDescending(item => item.CreatedAt)
            .FirstOrDefaultAsync(cancellationToken);

        var now = timeProvider.GetUtcNow();

        var workflow = new MaintenanceCoordinationWorkflow
        {
            MaintenanceRequestId = request.Id,
            Objective = WorkflowObjective,
            Status = MaintenanceCoordinationWorkflowStatus.Running,
            CurrentStep = 0,
            AgentVersion = null,
            RequiresHumanApproval = true,
            ApprovalStatus = MaintenanceCoordinationApprovalStatus.Pending,
            CreatedAt = now,
            UpdatedAt = now,
            Steps =
            [
                CreateStep("Maintenance data validation", 1, "Validate required maintenance request fields."),
                CreateStep("Maintenance coordination rules", 2, "Evaluate allow-listed maintenance readiness rules."),
                CreateStep("Maintenance coordination agent", 3, "Request advisory coordination recommendation from agent client.")
            ]
        };

        dbContext.MaintenanceCoordinationWorkflows.Add(workflow);
        await dbContext.SaveChangesAsync(cancellationToken);

        var validationResult = await ExecuteStepAsync(
            workflow,
            workflow.Steps.Single(step => step.StepOrder == 1),
            async token => await maintenanceRequestDataValidationTool.ValidateAsync(request, token),
            cancellationToken);

        if (validationResult is null)
        {
            return await FinalizeFailureAsync(workflow, cancellationToken);
        }

        var ruleResult = await ExecuteStepAsync(
            workflow,
            workflow.Steps.Single(step => step.StepOrder == 2),
            async token => await maintenanceCoordinationRuleTool.ValidateAsync(request, estimate, token),
            cancellationToken);

        if (ruleResult is null)
        {
            return await FinalizeFailureAsync(workflow, cancellationToken);
        }

        var agentRequest = CreateAgentRequest(request, estimate);
        var agentResponse = await ExecuteStepAsync(
            workflow,
            workflow.Steps.Single(step => step.StepOrder == 3),
            async token => await maintenanceCoordinationAgentClient.AnalyzeAsync(agentRequest, token),
            cancellationToken);

        if (agentResponse is null)
        {
            return await FinalizeFailureAsync(workflow, cancellationToken);
        }

        workflow.AgentVersion = agentResponse.Result.AgentVersion;
        workflow.FinalResultJson = JsonSerializer.Serialize(agentResponse.Result, new JsonSerializerOptions(JsonSerializerDefaults.Web));
        workflow.Status = MaintenanceCoordinationWorkflowStatus.AwaitingHumanReview;
        workflow.UpdatedAt = timeProvider.GetUtcNow();
        workflow.CurrentStep = 3;
        workflow.RequiresHumanApproval = true;
        workflow.ApprovalStatus = MaintenanceCoordinationApprovalStatus.Pending;
        workflow.ExecutionSummary = $"Completed deterministic validation and agent advisory review. Awaiting human approval. Steps executed: {string.Join(", ", workflow.Steps.OrderBy(step => step.StepOrder).Select(step => step.StepName))}.";

        await dbContext.SaveChangesAsync(cancellationToken);
        return workflow;
    }

    public async Task<MaintenanceCoordinationWorkflow?> GetByIdAsync(
        Guid workflowId,
        CancellationToken cancellationToken = default)
    {
        if (workflowId == Guid.Empty)
        {
            throw MaintenanceRequestServiceException.Validation("A maintenance coordination workflow ID is required.");
        }

        return await dbContext.MaintenanceCoordinationWorkflows
            .Include(item => item.Steps)
            .SingleOrDefaultAsync(item => item.Id == workflowId, cancellationToken);
    }

    public async Task<MaintenanceCoordinationWorkflow> ApproveAsync(
        Guid workflowId,
        Guid reviewerUserId,
        string? decisionNotes,
        CancellationToken cancellationToken = default)
    {
        if (workflowId == Guid.Empty)
        {
            throw MaintenanceRequestServiceException.Validation("A maintenance coordination workflow ID is required.");
        }

        if (reviewerUserId == Guid.Empty)
        {
            throw MaintenanceRequestServiceException.Validation("A reviewer user ID is required.");
        }

        var workflow = await dbContext.MaintenanceCoordinationWorkflows
            .Include(item => item.Steps)
            .SingleOrDefaultAsync(item => item.Id == workflowId, cancellationToken)
            ?? throw MaintenanceRequestServiceException.NotFound($"Maintenance coordination workflow '{workflowId}' was not found.");

        if (workflow.Status != MaintenanceCoordinationWorkflowStatus.AwaitingHumanReview)
        {
            throw MaintenanceRequestServiceException.Conflict(
                "This maintenance coordination workflow is not awaiting human approval.");
        }

        var decisionAt = timeProvider.GetUtcNow();
        var safeDecisionNotes = string.IsNullOrWhiteSpace(decisionNotes) ? "Approved by the authorized reviewer." : decisionNotes.Trim();

        workflow.RequiresHumanApproval = true;
        workflow.ApprovalStatus = MaintenanceCoordinationApprovalStatus.Approved;
        workflow.Status = MaintenanceCoordinationWorkflowStatus.Completed;
        workflow.UpdatedAt = decisionAt;
        workflow.ExecutionSummary = string.IsNullOrWhiteSpace(workflow.ExecutionSummary)
            ? $"Approved by reviewer '{reviewerUserId}' at {decisionAt:O}."
            : $"{workflow.ExecutionSummary} Approved by reviewer '{reviewerUserId}' at {decisionAt:O}.";
        workflow.ErrorMessage = null;
        workflow.FinalResultJson = AppendDecisionToResult(workflow.FinalResultJson, new
        {
            decision = "approved",
            reviewerUserId,
            decisionNotes = safeDecisionNotes,
            decidedAt = decisionAt
        });

        await dbContext.SaveChangesAsync(cancellationToken);
        return workflow;
    }

    public async Task<MaintenanceCoordinationWorkflow> RejectAsync(
        Guid workflowId,
        Guid reviewerUserId,
        string? decisionNotes,
        CancellationToken cancellationToken = default)
    {
        if (workflowId == Guid.Empty)
        {
            throw MaintenanceRequestServiceException.Validation("A maintenance coordination workflow ID is required.");
        }

        if (reviewerUserId == Guid.Empty)
        {
            throw MaintenanceRequestServiceException.Validation("A reviewer user ID is required.");
        }

        var workflow = await dbContext.MaintenanceCoordinationWorkflows
            .Include(item => item.Steps)
            .SingleOrDefaultAsync(item => item.Id == workflowId, cancellationToken)
            ?? throw MaintenanceRequestServiceException.NotFound($"Maintenance coordination workflow '{workflowId}' was not found.");

        if (workflow.Status != MaintenanceCoordinationWorkflowStatus.AwaitingHumanReview)
        {
            throw MaintenanceRequestServiceException.Conflict(
                "This maintenance coordination workflow is not awaiting human approval.");
        }

        var decisionAt = timeProvider.GetUtcNow();
        var safeDecisionNotes = string.IsNullOrWhiteSpace(decisionNotes) ? "Rejected by the authorized reviewer." : decisionNotes.Trim();

        workflow.RequiresHumanApproval = true;
        workflow.ApprovalStatus = MaintenanceCoordinationApprovalStatus.Rejected;
        workflow.Status = MaintenanceCoordinationWorkflowStatus.Failed;
        workflow.UpdatedAt = decisionAt;
        workflow.ErrorMessage = safeDecisionNotes;
        workflow.ExecutionSummary = string.IsNullOrWhiteSpace(workflow.ExecutionSummary)
            ? $"Rejected by reviewer '{reviewerUserId}' at {decisionAt:O}."
            : $"{workflow.ExecutionSummary} Rejected by reviewer '{reviewerUserId}' at {decisionAt:O}.";
        workflow.FinalResultJson = AppendDecisionToResult(workflow.FinalResultJson, new
        {
            decision = "rejected",
            reviewerUserId,
            decisionNotes = safeDecisionNotes,
            decidedAt = decisionAt
        });

        await dbContext.SaveChangesAsync(cancellationToken);
        return workflow;
    }

    private async Task<T?> ExecuteStepAsync<T>(
        MaintenanceCoordinationWorkflow workflow,
        MaintenanceCoordinationStep step,
        Func<CancellationToken, Task<T>> execute,
        CancellationToken cancellationToken)
        where T : class
    {
        var startedAt = timeProvider.GetUtcNow();
        step.Status = MaintenanceCoordinationStepStatus.Running;
        step.StartedAt = startedAt;
        step.InputSummary = step.InputSummary ?? "Maintenance coordination step input.";
        workflow.CurrentStep = step.StepOrder;
        workflow.UpdatedAt = startedAt;
        await dbContext.SaveChangesAsync(cancellationToken);

        try
        {
            var result = await execute(cancellationToken)
                ?? throw new InvalidOperationException("The maintenance tool returned no result.");

            step.OutputSummary = TruncateToLength(JsonSerializer.Serialize(result, new JsonSerializerOptions(JsonSerializerDefaults.Web)), 4000);
            step.Status = MaintenanceCoordinationStepStatus.Completed;
            step.CompletedAt = timeProvider.GetUtcNow();
            step.ValidationSummary = CreateValidationSummary(result);
            workflow.UpdatedAt = step.CompletedAt.Value;
            await dbContext.SaveChangesAsync(cancellationToken);
            return result;
        }
        catch (Exception exception) when (
            exception is not OperationCanceledException || !cancellationToken.IsCancellationRequested)
        {
            logger.LogError(exception, "Maintenance coordination workflow {WorkflowId} failed at step {StepOrder}.", workflow.Id, step.StepOrder);

            var failedAt = timeProvider.GetUtcNow();
            step.Status = MaintenanceCoordinationStepStatus.Failed;
            step.ErrorMessage = SafeStepErrorMessage;
            step.CompletedAt = failedAt;
            workflow.Status = MaintenanceCoordinationWorkflowStatus.Failed;
            workflow.ErrorMessage = SafeStepErrorMessage;
            workflow.UpdatedAt = failedAt;
            await dbContext.SaveChangesAsync(CancellationToken.None);
            return null;
        }
    }

    private async Task<MaintenanceCoordinationWorkflow> FinalizeFailureAsync(
        MaintenanceCoordinationWorkflow workflow,
        CancellationToken cancellationToken)
    {
        workflow.Status = MaintenanceCoordinationWorkflowStatus.Failed;
        workflow.ErrorMessage = workflow.ErrorMessage ?? SafeStepErrorMessage;
        workflow.UpdatedAt = timeProvider.GetUtcNow();
        workflow.RequiresHumanApproval = true;
        workflow.ApprovalStatus = MaintenanceCoordinationApprovalStatus.Pending;
        await dbContext.SaveChangesAsync(cancellationToken);
        return workflow;
    }

    private static MaintenanceCoordinationStep CreateStep(string stepName, int stepOrder, string inputSummary)
        => new()
        {
            StepName = stepName,
            StepOrder = stepOrder,
            Status = MaintenanceCoordinationStepStatus.Pending,
            InputSummary = inputSummary
        };

    private static MaintenanceCoordinationAgentRequest CreateAgentRequest(
        MaintenanceRequest request,
        RepairEstimate? estimate)
    {
        return new MaintenanceCoordinationAgentRequest
        {
            MaintenanceRequestId = request.Id,
            Title = request.Title,
            Description = request.Description,
            Category = request.Category.ToString().ToLowerInvariant(),
            Priority = request.Priority switch
            {
                MaintenancePriority.Low => "low",
                MaintenancePriority.Normal => "medium",
                MaintenancePriority.High => "high",
                MaintenancePriority.Emergency => "urgent",
                _ => "medium"
            },
            CurrentStatus = request.Status switch
            {
                MaintenanceRequestStatus.InProgress => "in_progress",
                MaintenanceRequestStatus.Completed => "completed",
                MaintenanceRequestStatus.Cancelled => "cancelled",
                _ => "open"
            },
            AssignedTechnicianId = request.TechnicianId,
            RepairEstimate = estimate is null ? null : new MaintenanceCoordinationEstimate
            {
                Amount = estimate.TotalCost,
                Currency = "USD",
                Notes = estimate.Notes
            },
            Attachments = []
        };
    }

    private static string CreateValidationSummary(object result)
    {
        return result switch
        {
            MaintenanceDataValidationResult validation => $"Valid={validation.IsValid}; completeness={validation.CompletenessScore}; missing={validation.MissingFields.Count}; warnings={validation.Warnings.Count}",
            MaintenanceCoordinationRuleValidationResult rules => $"Passed={rules.Passed}; failed={rules.FailedRules.Count}; warnings={rules.Warnings.Count}",
            MaintenanceCoordinationAgentResponse agent => $"Agent result valid; priority={agent.Result.RecommendedPriority}; nextAction={agent.Result.NextAction}; warnings={agent.Result.Warnings.Count}",
            _ => "Validation summary recorded."
        };
    }

    private static string AppendDecisionToResult(string? currentPayload, object decision)
    {
        if (string.IsNullOrWhiteSpace(currentPayload))
        {
            return JsonSerializer.Serialize(decision, new JsonSerializerOptions(JsonSerializerDefaults.Web));
        }

        try
        {
            using var document = JsonDocument.Parse(currentPayload);
            var root = JsonDocument.Parse(JsonSerializer.Serialize(new { decision = document.RootElement.Clone(), decisionDetails = decision }, new JsonSerializerOptions(JsonSerializerDefaults.Web))).RootElement;
            return JsonSerializer.Serialize(root, new JsonSerializerOptions(JsonSerializerDefaults.Web));
        }
        catch (JsonException)
        {
            return JsonSerializer.Serialize(new { previousResult = currentPayload, decisionDetails = decision }, new JsonSerializerOptions(JsonSerializerDefaults.Web));
        }
    }

    private static string TruncateToLength(string value, int maxLength)
        => value.Length <= maxLength ? value : value[..maxLength];
}
