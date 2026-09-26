using System.Text.Json;
using RentFlow.Api.DTOs.PricingAnalysis;
using RentFlow.Api.Models;

namespace RentFlow.Api.Services;

internal static class PricingAnalysisWorkflowResponseMapper
{
    internal static PricingAnalysisWorkflowResponseDto Map(PricingAnalysisWorkflow workflow)
    {
        PricingAnalysisResultDto? result = null;
        if (!string.IsNullOrWhiteSpace(workflow.ResultJson))
        {
            try
            {
                result = JsonSerializer.Deserialize<PricingAnalysisResultDto>(
                    workflow.ResultJson,
                    PricingAnalysisResponseMapper.JsonOptions);
            }
            catch (JsonException)
            {
                result = null;
            }
        }

        return new PricingAnalysisWorkflowResponseDto
        {
            WorkflowId = workflow.Id,
            PropertyId = workflow.PropertyId,
            Status = workflow.Status,
            Objective = workflow.Objective,
            CurrentStep = workflow.CurrentStep,
            EvidencePolicyVersion = workflow.EvidencePolicyVersion,
            EvidenceSufficiency = workflow.EvidenceSufficiency,
            Confidence = workflow.Confidence,
            Result = result,
            ErrorMessage = SafeError(workflow.ErrorMessage),
            CreatedAt = workflow.CreatedAt,
            UpdatedAt = workflow.UpdatedAt,
            StartedAt = workflow.StartedAt,
            CompletedAt = workflow.CompletedAt,
            Steps = workflow.Steps
                .OrderBy(step => step.StepOrder)
                .Select(step => new PricingAnalysisWorkflowStepResponseDto
                {
                    Order = step.StepOrder,
                    Name = step.StepName,
                    Status = step.Status,
                    OutputSummary = step.OutputSummary,
                    ValidationSummary = step.ValidationSummary,
                    ErrorMessage = SafeError(step.ErrorMessage),
                    StartedAt = step.StartedAt,
                    CompletedAt = step.CompletedAt
                })
                .ToArray()
        };
    }

    private static string? SafeError(string? message)
    {
        if (string.IsNullOrWhiteSpace(message))
        {
            return null;
        }

        return message switch
        {
            "The pricing analysis step failed unexpectedly." => message,
            "The pricing analysis agent is not configured correctly." => message,
            "The pricing analysis agent timed out." => message,
            "The pricing analysis agent is unavailable." => message,
            "The pricing analysis agent returned an unsuccessful response." => message,
            "The pricing analysis agent returned an invalid response." => message,
            "Pricing analysis was cancelled before completion." => message,
            _ => "The pricing analysis workflow failed unexpectedly."
        };
    }
}
