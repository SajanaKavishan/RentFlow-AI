using System.Text.Json;
using RentFlow.Api.DTOs.ApplicationValidation;
using RentFlow.Api.Models;

namespace RentFlow.Api.Services;

internal static class ApplicationValidationResponseMapper
{
    internal static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    public static ApplicationValidationWorkflowResponseDto Map(ApplicationValidationWorkflow workflow)
    {
        var orderedSteps = workflow.Steps.OrderBy(step => step.StepOrder).ToArray();

        return new ApplicationValidationWorkflowResponseDto
        {
            Id = workflow.Id,
            ApplicationId = workflow.ApplicationId,
            Objective = workflow.Objective,
            Status = workflow.Status,
            CurrentStep = workflow.CurrentStep,
            CompletenessScore = workflow.CompletenessScore,
            Recommendation = workflow.Recommendation,
            RequiresHumanApproval = workflow.RequiresHumanApproval,
            CreatedAt = workflow.CreatedAt,
            UpdatedAt = workflow.UpdatedAt,
            Steps = orderedSteps.Select(MapStep).ToArray(),
            Summary = CreateSummary(workflow, orderedSteps)
        };
    }

    private static ApplicationValidationStepResponseDto MapStep(ApplicationValidationStep step)
    {
        return new ApplicationValidationStepResponseDto
        {
            Id = step.Id,
            AgentName = step.AgentName,
            StepOrder = step.StepOrder,
            Status = step.Status,
            InputSummary = step.InputSummary,
            ResultJson = step.ResultJson,
            ErrorMessage = step.ErrorMessage,
            StartedAt = step.StartedAt,
            CompletedAt = step.CompletedAt
        };
    }

    private static ApplicationValidationSummaryDto? CreateSummary(
        ApplicationValidationWorkflow workflow,
        IReadOnlyList<ApplicationValidationStep> steps)
    {
        if (workflow.CompletenessScore is null
            || workflow.Recommendation is null
            || steps.Count != 3
            || steps.Any(step => step.Status != ApplicationValidationStepStatus.Completed))
        {
            return null;
        }

        var applicationData = Deserialize<ApplicationDataValidationResult>(steps[0].ResultJson);
        var documents = Deserialize<DocumentValidationResult>(steps[1].ResultJson);
        var deterministicRules = Deserialize<DeterministicRuleValidationResult>(steps[2].ResultJson);

        if (applicationData is null || documents is null || deterministicRules is null)
        {
            return null;
        }

        return new ApplicationValidationSummaryDto
        {
            CompletenessScore = workflow.CompletenessScore.Value,
            Recommendation = workflow.Recommendation,
            RequiresHumanApproval = workflow.RequiresHumanApproval,
            ApplicationData = applicationData,
            Documents = documents,
            DeterministicRules = deterministicRules
        };
    }

    private static T? Deserialize<T>(string? json)
    {
        if (string.IsNullOrWhiteSpace(json))
        {
            return default;
        }

        try
        {
            return JsonSerializer.Deserialize<T>(json, JsonOptions);
        }
        catch (JsonException)
        {
            return default;
        }
    }
}
