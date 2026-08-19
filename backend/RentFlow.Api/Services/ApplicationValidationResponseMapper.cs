using System.Text.Json;
using RentFlow.Api.DTOs.ApplicationValidation;
using RentFlow.Api.Models;

namespace RentFlow.Api.Services;

internal static class ApplicationValidationResponseMapper
{
    private const string SafeStepErrorMessage = "The validation step failed unexpectedly.";

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
            AgentName = step.AgentName,
            StepOrder = step.StepOrder,
            Status = step.Status,
            Result = ParseStructuredResult(step.StepOrder, step.ResultJson),
            ErrorMessage = string.IsNullOrWhiteSpace(step.ErrorMessage)
                ? null
                : SafeStepErrorMessage,
            StartedAt = step.StartedAt,
            CompletedAt = step.CompletedAt
        };
    }

    private static JsonElement? ParseStructuredResult(int stepOrder, string? json)
    {
        object? result = stepOrder switch
        {
            1 => Deserialize<ApplicationDataValidationResult>(json),
            2 => Deserialize<DocumentValidationResult>(json),
            3 => Deserialize<DeterministicRuleValidationResult>(json),
            4 => Deserialize<AgenticApplicationReviewResult>(json),
            _ => null
        };

        return result is null
            ? null
            : JsonSerializer.SerializeToElement(result, result.GetType(), JsonOptions);
    }

    private static ApplicationValidationSummaryDto? CreateSummary(
        ApplicationValidationWorkflow workflow,
        IReadOnlyList<ApplicationValidationStep> steps)
    {
        if (workflow.CompletenessScore is null
            || workflow.Recommendation is null
            || steps.Count is not (3 or 4)
            || steps.Any(step => step.Status != ApplicationValidationStepStatus.Completed))
        {
            return null;
        }

        var applicationData = Deserialize<ApplicationDataValidationResult>(steps[0].ResultJson);
        var documents = Deserialize<DocumentValidationResult>(steps[1].ResultJson);
        var deterministicRules = Deserialize<DeterministicRuleValidationResult>(steps[2].ResultJson);
        var agenticReview = steps.Count == 4
            ? Deserialize<AgenticApplicationReviewResult>(steps[3].ResultJson)
            : null;

        if (applicationData is null
            || documents is null
            || deterministicRules is null
            || (steps.Count == 4 && agenticReview is null))
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
            DeterministicRules = deterministicRules,
            AgenticReview = agenticReview
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
