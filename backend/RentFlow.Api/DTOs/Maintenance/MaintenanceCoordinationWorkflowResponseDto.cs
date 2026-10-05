using RentFlow.Api.Models;
using System.Text.Json;

namespace RentFlow.Api.DTOs.Maintenance;

public sealed class MaintenanceCoordinationWorkflowResponseDto
{
    public Guid Id { get; init; }

    public Guid MaintenanceRequestId { get; init; }

    public string Objective { get; init; } = string.Empty;

    public MaintenanceCoordinationWorkflowStatus Status { get; init; }

    public int CurrentStep { get; init; }

    public string? AgentVersion { get; init; }

    public string? PlanSummary { get; init; }

    public string? ExecutionSummary { get; init; }

    public string? FinalResultJson { get; init; }

    public string? ErrorMessage { get; init; }

    public MaintenancePhotoEvidenceSummary? PhotoEvidence { get; init; }

    public bool RequiresHumanApproval { get; init; }

    public MaintenanceCoordinationApprovalStatus ApprovalStatus { get; init; }

    public DateTimeOffset CreatedAt { get; init; }

    public DateTimeOffset UpdatedAt { get; init; }

    public IReadOnlyCollection<MaintenanceCoordinationStepResponseDto> Steps { get; init; } = [];

    public static MaintenanceCoordinationWorkflowResponseDto FromWorkflow(
        MaintenanceCoordinationWorkflow workflow)
    {
        ArgumentNullException.ThrowIfNull(workflow);

        return new MaintenanceCoordinationWorkflowResponseDto
        {
            Id = workflow.Id,
            MaintenanceRequestId = workflow.MaintenanceRequestId,
            Objective = workflow.Objective,
            Status = workflow.Status,
            CurrentStep = workflow.CurrentStep,
            AgentVersion = workflow.AgentVersion,
            PlanSummary = workflow.PlanSummary,
            ExecutionSummary = workflow.ExecutionSummary,
            FinalResultJson = workflow.FinalResultJson,
            ErrorMessage = workflow.ErrorMessage,
            PhotoEvidence = ReadPhotoEvidence(workflow),
            RequiresHumanApproval = workflow.RequiresHumanApproval,
            ApprovalStatus = workflow.ApprovalStatus,
            CreatedAt = workflow.CreatedAt,
            UpdatedAt = workflow.UpdatedAt,
            Steps = workflow.Steps
                .OrderBy(step => step.StepOrder)
                .Select(MaintenanceCoordinationStepResponseDto.FromStep)
                .ToArray()
        };
    }

    private static MaintenancePhotoEvidenceSummary? ReadPhotoEvidence(MaintenanceCoordinationWorkflow workflow)
    {
        var summary = workflow.Steps.FirstOrDefault(step => step.StepOrder == 3
            && step.Status == MaintenanceCoordinationStepStatus.Completed)?.ValidationSummary;
        if (string.IsNullOrWhiteSpace(summary) || !summary.StartsWith('{')) return null;
        try
        {
            var evidence = JsonSerializer.Deserialize<MaintenancePhotoEvidenceSummary>(summary,
                new JsonSerializerOptions(JsonSerializerDefaults.Web));
            return evidence?.IsValid == true ? evidence : null;
        }
        catch (JsonException) { return null; }
    }
}

public sealed class MaintenanceCoordinationStepResponseDto
{
    public Guid Id { get; init; }

    public Guid WorkflowId { get; init; }

    public string StepName { get; init; } = string.Empty;

    public int StepOrder { get; init; }

    public MaintenanceCoordinationStepStatus Status { get; init; }

    public string? InputSummary { get; init; }

    public string? OutputSummary { get; init; }

    public string? ValidationSummary { get; init; }

    public string? ErrorMessage { get; init; }

    public DateTimeOffset? StartedAt { get; init; }

    public DateTimeOffset? CompletedAt { get; init; }

    internal static MaintenanceCoordinationStepResponseDto FromStep(
        MaintenanceCoordinationStep step)
        => new()
        {
            Id = step.Id,
            WorkflowId = step.WorkflowId,
            StepName = step.StepName,
            StepOrder = step.StepOrder,
            Status = step.Status,
            InputSummary = step.InputSummary,
            OutputSummary = step.OutputSummary,
            ValidationSummary = step.ValidationSummary,
            ErrorMessage = step.ErrorMessage,
            StartedAt = step.StartedAt,
            CompletedAt = step.CompletedAt
        };
}
