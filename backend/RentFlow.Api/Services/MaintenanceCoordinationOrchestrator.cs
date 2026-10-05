using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.Extensions.Options;
using RentFlow.Api.Configuration;
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
    ILogger<MaintenanceCoordinationOrchestrator> logger,
    IOptions<AgentServiceOptions>? agentOptions = null,
    IMaintenancePhotoEvidenceService? photoEvidenceService = null) : IMaintenanceCoordinationOrchestrator
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
        var callerToken = cancellationToken;
        var started = System.Diagnostics.Stopwatch.StartNew();
        var totalSeconds = agentOptions?.Value.TimeoutSeconds ?? 30;
        using var budget = CancellationTokenSource.CreateLinkedTokenSource(callerToken);
        budget.CancelAfter(TimeSpan.FromSeconds(totalSeconds));
        cancellationToken = budget.Token;

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
        try
        {
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

            if (!validationResult.IsValid || !ruleResult.Passed)
            {
                return await FinalizeDeterministicValidationFailureAsync(
                    workflow,
                    validationResult,
                    ruleResult,
                    cancellationToken);
            }

            var attachments = await dbContext.MaintenanceAttachments.AsNoTracking()
                .Where(item => item.MaintenanceRequestId == maintenanceRequestId).ToListAsync(cancellationToken);
            var agentRequest = MaintenanceCoordinationRequestMapper.Map(request, estimate, attachments);
            var agentResponse = await ExecuteStepAsync(
                workflow,
                workflow.Steps.Single(step => step.StepOrder == 3),
                async token =>
                {
                    if (photoEvidenceService is not null)
                        await photoEvidenceService.PrepareAsync(request, attachments, agentRequest, token);
                    token.ThrowIfCancellationRequested();
                    agentRequest.RemainingBudgetSeconds = Math.Max(0.1, totalSeconds - started.Elapsed.TotalSeconds - 0.5);
                    var response = await maintenanceCoordinationAgentClient.AnalyzeAsync(agentRequest, token);
                    var current = await dbContext.MaintenanceRequests.AsNoTracking().SingleAsync(item => item.Id == request.Id, token);
                    if (current.Status.ToString() != agentRequest.CurrentStatus)
                        throw new MaintenanceCoordinationAgentClientException(MaintenanceCoordinationAgentClientError.MalformedResponse, "The request changed during analysis.");
                    MaintenanceCoordinationResultValidator.Validate(agentRequest, response);
                    return response;
                },
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
        catch (OperationCanceledException)
        {
            workflow.ErrorMessage = "The maintenance coordination analysis was cancelled or timed out.";
            foreach (var step in workflow.Steps.Where(step => step.Status == MaintenanceCoordinationStepStatus.Running))
            {
                step.Status = MaintenanceCoordinationStepStatus.Failed;
                step.ErrorMessage = workflow.ErrorMessage;
                step.CompletedAt = timeProvider.GetUtcNow();
            }
            var failed = await FinalizeFailureAsync(workflow, CancellationToken.None);
            if (callerToken.IsCancellationRequested) throw;
            return failed;
        }
        catch (Exception exception)
        {
            logger.LogWarning("Maintenance coordination workflow {WorkflowId} aborted ({ErrorType}).", workflow.Id, exception.GetType().Name);
            workflow.ErrorMessage = SafeStepErrorMessage;
            foreach (var step in workflow.Steps.Where(step => step.Status == MaintenanceCoordinationStepStatus.Running))
            {
                step.Status = MaintenanceCoordinationStepStatus.Failed;
                step.ErrorMessage = SafeStepErrorMessage;
                step.CompletedAt = timeProvider.GetUtcNow();
            }
            return await FinalizeFailureAsync(workflow, CancellationToken.None);
        }
    }

    private async Task<MaintenanceCoordinationWorkflow> FinalizeDeterministicValidationFailureAsync(
        MaintenanceCoordinationWorkflow workflow,
        MaintenanceDataValidationResult validationResult,
        MaintenanceCoordinationRuleValidationResult ruleResult,
        CancellationToken cancellationToken)
    {
        var failureReasons = new List<string>();
        if (!validationResult.IsValid)
        {
            var detail = validationResult.MissingFields.Count > 0
                ? $" Missing required fields: {string.Join(", ", validationResult.MissingFields)}."
                : " Required maintenance data checks did not pass.";
            failureReasons.Add($"Maintenance data validation failed.{detail}");
        }

        if (!ruleResult.Passed)
        {
            var detail = ruleResult.FailedRules.Count > 0
                ? string.Join(", ", ruleResult.FailedRules)
                : "One or more maintenance coordination rules did not pass.";
            failureReasons.Add($"Maintenance coordination rules failed: {detail}.");
        }

        var failureReason = string.Join(" ", failureReasons);
        workflow.Status = MaintenanceCoordinationWorkflowStatus.Failed;
        workflow.CurrentStep = 2;
        workflow.ErrorMessage = failureReason;
        workflow.RequiresHumanApproval = false;
        workflow.ApprovalStatus = MaintenanceCoordinationApprovalStatus.NotRequired;
        workflow.UpdatedAt = timeProvider.GetUtcNow();
        workflow.ExecutionSummary =
            $"Workflow stopped before AI agent execution because deterministic checks failed. {failureReason} Deterministic validation results were persisted.";

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

    public async Task<MaintenanceCoordinationWorkflow?> GetLatestByRequestAsync(
        Guid maintenanceRequestId,
        CancellationToken cancellationToken = default)
    {
        if (maintenanceRequestId == Guid.Empty)
            throw MaintenanceRequestServiceException.Validation("A maintenance request ID is required.");

        return await dbContext.MaintenanceCoordinationWorkflows
            .AsNoTracking()
            .Include(item => item.Steps)
            .Where(item => item.MaintenanceRequestId == maintenanceRequestId)
            .OrderByDescending(item => item.CreatedAt)
            .ThenByDescending(item => item.Id)
            .FirstOrDefaultAsync(cancellationToken);
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
            logger.LogWarning("Maintenance coordination workflow {WorkflowId} failed at step {StepOrder} ({ErrorType}).", workflow.Id, step.StepOrder, exception.GetType().Name);

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
        workflow.FinalResultJson = null;
        workflow.UpdatedAt = timeProvider.GetUtcNow();
        workflow.RequiresHumanApproval = false;
        workflow.ApprovalStatus = MaintenanceCoordinationApprovalStatus.NotRequired;
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

    private static string CreateValidationSummary(object result)
    {
        return result switch
        {
            MaintenanceDataValidationResult validation => $"Valid={validation.IsValid}; completeness={validation.CompletenessScore}; missing={validation.MissingFields.Count}; warnings={validation.Warnings.Count}",
            MaintenanceCoordinationRuleValidationResult rules => $"Passed={rules.Passed}; failed={rules.FailedRules.Count}; warnings={rules.Warnings.Count}",
            MaintenanceCoordinationAgentResponse { ExecutionMetadata.PhotoEvidence: { } evidence } =>
                JsonSerializer.Serialize(evidence, new JsonSerializerOptions(JsonSerializerDefaults.Web)),
            MaintenanceCoordinationAgentResponse agent => $"Agent result valid; priority={agent.Result.SuggestedPriority}; nextAction={agent.Result.NextAction}; warnings={agent.Result.ValidationFlags.Count}",
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
            var root = JsonNode.Parse(currentPayload)?.AsObject() ?? throw new JsonException();
            root["decisionDetails"] = JsonSerializer.SerializeToNode(decision, new JsonSerializerOptions(JsonSerializerDefaults.Web));
            return root.ToJsonString(new JsonSerializerOptions(JsonSerializerDefaults.Web));
        }
        catch (JsonException)
        {
            return JsonSerializer.Serialize(new { previousResult = currentPayload, decisionDetails = decision }, new JsonSerializerOptions(JsonSerializerDefaults.Web));
        }
    }

    private static string TruncateToLength(string value, int maxLength)
        => value.Length <= maxLength ? value : value[..maxLength];
}
