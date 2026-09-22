using RentFlow.Api.DTOs.Maintenance;
using RentFlow.Api.Models;
using RentFlow.Api.Services.Interfaces;

namespace RentFlow.Api.Services;

/// <summary>
/// Applies allow-listed maintenance coordination rules without changing status or approvals.
/// </summary>
public class MaintenanceCoordinationRuleTool : IMaintenanceCoordinationRuleTool
{
    public const string RequestExistsRule = "MaintenanceRequestExists";
    public const string CategoryProvidedRule = "MaintenanceCategoryIsDefined";
    public const string PriorityProvidedRule = "MaintenancePriorityIsDefined";
    public const string DescriptionPresentRule = "MaintenanceDescriptionIsPresent";
    public const string EstimateReadyForReviewRule = "RepairEstimateReadyForReview";

    public Task<MaintenanceCoordinationRuleValidationResult> ValidateAsync(
        MaintenanceRequest? request,
        RepairEstimate? estimate = null,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(request);
        cancellationToken.ThrowIfCancellationRequested();

        var passedRules = new List<string>();
        var failedRules = new List<string>();
        var warnings = new List<string>();

        var category = request.Category;
        var priority = request.Priority;
        var description = request.Description ?? string.Empty;

        Record(request is not null, RequestExistsRule, passedRules, failedRules);
        Record(Enum.IsDefined(category), CategoryProvidedRule, passedRules, failedRules);
        Record(Enum.IsDefined(priority), PriorityProvidedRule, passedRules, failedRules);
        Record(!string.IsNullOrWhiteSpace(description), DescriptionPresentRule, passedRules, failedRules);

        if (estimate is not null)
        {
            Record(
                estimate.TotalCost >= 0m,
                EstimateReadyForReviewRule,
                passedRules,
                failedRules);
        }
        else
        {
            warnings.Add("No repair estimate was provided; review will continue with incomplete estimate information.");
        }

        return Task.FromResult(new MaintenanceCoordinationRuleValidationResult
        {
            Passed = failedRules.Count == 0,
            PassedRules = passedRules,
            FailedRules = failedRules,
            Warnings = warnings
        });
    }

    private static void Record(
        bool passed,
        string rule,
        ICollection<string> passedRules,
        ICollection<string> failedRules)
    {
        (passed ? passedRules : failedRules).Add(rule);
    }
}
