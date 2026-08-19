using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using RentFlow.Api.Data;
using RentFlow.Api.DTOs.ApplicationValidation;
using RentFlow.Api.Models;
using RentFlow.Api.Services.Interfaces;

namespace RentFlow.Api.Services;

/// <summary>
/// Coordinates allow-listed deterministic validation tools and persists an auditable workflow.
/// </summary>
public class ApplicationValidationOrchestrator(
    ApplicationDbContext dbContext,
    IApplicationDataValidationTool applicationDataValidationTool,
    IDocumentValidationTool documentValidationTool,
    IDeterministicApplicationRuleTool deterministicRuleTool,
    TimeProvider timeProvider,
    ILogger<ApplicationValidationOrchestrator> logger) : IApplicationValidationOrchestrator
{
    private const string WorkflowObjective =
        "Validate submitted rental application data and document metadata for landlord review.";
    private const string SafeStepErrorMessage = "The validation step failed unexpectedly.";

    public async Task<ApplicationValidationWorkflowResponseDto> StartValidationAsync(
        Guid applicationId,
        CancellationToken cancellationToken = default)
    {
        if (applicationId == Guid.Empty)
        {
            throw new ApplicationValidationException(
                ApplicationValidationError.Validation,
                "An application ID is required.");
        }

        var application = await dbContext.RentalApplications
            .SingleOrDefaultAsync(item => item.Id == applicationId, cancellationToken)
            ?? throw new ApplicationValidationException(
                ApplicationValidationError.NotFound,
                $"Rental application '{applicationId}' was not found.");

        if (application.Status is not RentalApplicationStatus.Submitted
            and not RentalApplicationStatus.UnderReview)
        {
            throw new ApplicationValidationException(
                ApplicationValidationError.Conflict,
                $"A {application.Status} application is not eligible for validation.");
        }

        var documents = await dbContext.ApplicationDocuments
            .AsNoTracking()
            .Where(document => document.ApplicationId == applicationId)
            .ToListAsync(cancellationToken);

        var now = timeProvider.GetUtcNow();
        var workflow = new ApplicationValidationWorkflow
        {
            ApplicationId = applicationId,
            Objective = WorkflowObjective,
            Status = ApplicationValidationWorkflowStatus.Running,
            CurrentStep = 0,
            RequiresHumanApproval = true,
            CreatedAt = now,
            UpdatedAt = now,
            Steps =
            [
                CreateStep("Application Data Validator", 1,
                    "Current rental application fields required by business rules."),
                CreateStep("Document Validation Agent", 2,
                    $"{documents.Count} application document metadata record(s)."),
                CreateStep("Deterministic Rule Checker", 3,
                    "Allow-listed eligibility, income, move-in date, and document-presence rules.")
            ]
        };

        dbContext.ApplicationValidationWorkflows.Add(workflow);
        await dbContext.SaveChangesAsync(cancellationToken);

        var applicationDataResult = await ExecuteStepAsync(
            workflow,
            workflow.Steps.Single(step => step.StepOrder == 1),
            token => applicationDataValidationTool.ValidateAsync(application, token),
            cancellationToken);
        if (applicationDataResult is null)
        {
            return ApplicationValidationResponseMapper.Map(workflow);
        }

        var documentResult = await ExecuteStepAsync(
            workflow,
            workflow.Steps.Single(step => step.StepOrder == 2),
            token => documentValidationTool.ValidateAsync(documents, token),
            cancellationToken);
        if (documentResult is null)
        {
            return ApplicationValidationResponseMapper.Map(workflow);
        }

        var ruleResult = await ExecuteStepAsync(
            workflow,
            workflow.Steps.Single(step => step.StepOrder == 3),
            token => deterministicRuleTool.ValidateAsync(application, documents, token),
            cancellationToken);
        if (ruleResult is null)
        {
            return ApplicationValidationResponseMapper.Map(workflow);
        }

        workflow.CompletenessScore = applicationDataResult.CompletenessScore;
        workflow.Recommendation = DetermineRecommendation(
            applicationDataResult,
            documentResult,
            ruleResult);
        workflow.RequiresHumanApproval = true;
        workflow.Status = ApplicationValidationWorkflowStatus.AwaitingHumanReview;
        workflow.UpdatedAt = timeProvider.GetUtcNow();
        await dbContext.SaveChangesAsync(cancellationToken);

        return ApplicationValidationResponseMapper.Map(workflow);
    }

    private async Task<T?> ExecuteStepAsync<T>(
        ApplicationValidationWorkflow workflow,
        ApplicationValidationStep step,
        Func<CancellationToken, Task<T>> execute,
        CancellationToken cancellationToken)
        where T : class
    {
        var now = timeProvider.GetUtcNow();
        step.Status = ApplicationValidationStepStatus.Running;
        step.StartedAt = now;
        workflow.CurrentStep = step.StepOrder;
        workflow.UpdatedAt = now;
        await dbContext.SaveChangesAsync(cancellationToken);

        try
        {
            var result = await execute(cancellationToken)
                ?? throw new InvalidOperationException("The validation tool returned no result.");
            step.ResultJson = JsonSerializer.Serialize(
                result,
                ApplicationValidationResponseMapper.JsonOptions);
            step.Status = ApplicationValidationStepStatus.Completed;
            step.CompletedAt = timeProvider.GetUtcNow();
            workflow.UpdatedAt = step.CompletedAt.Value;
            await dbContext.SaveChangesAsync(cancellationToken);
            return result;
        }
        catch (Exception exception) when (
            exception is not OperationCanceledException || !cancellationToken.IsCancellationRequested)
        {
            logger.LogError(
                exception,
                "Application validation workflow {WorkflowId} failed at step {StepOrder}.",
                workflow.Id,
                step.StepOrder);

            var failedAt = timeProvider.GetUtcNow();
            step.Status = ApplicationValidationStepStatus.Failed;
            step.ErrorMessage = SafeStepErrorMessage;
            step.CompletedAt = failedAt;
            workflow.Status = ApplicationValidationWorkflowStatus.Failed;
            workflow.UpdatedAt = failedAt;
            await dbContext.SaveChangesAsync(CancellationToken.None);
            return null;
        }
    }

    private static ApplicationValidationStep CreateStep(
        string agentName,
        int stepOrder,
        string inputSummary)
    {
        return new ApplicationValidationStep
        {
            AgentName = agentName,
            StepOrder = stepOrder,
            Status = ApplicationValidationStepStatus.Pending,
            InputSummary = inputSummary
        };
    }

    private static string DetermineRecommendation(
        ApplicationDataValidationResult applicationData,
        DocumentValidationResult documents,
        DeterministicRuleValidationResult rules)
    {
        if (!applicationData.IsValid)
        {
            return "Request missing information";
        }

        if (!documents.IsValid
            || rules.FailedRules.Contains(
                DeterministicApplicationRuleTool.RequiredDocumentsRule,
                StringComparer.Ordinal))
        {
            return "Request missing documents";
        }

        return rules.Passed
            ? "Ready for landlord review"
            : "Request missing information";
    }
}
