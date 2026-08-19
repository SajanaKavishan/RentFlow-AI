using RentFlow.Api.DTOs.ApplicationValidation;
using RentFlow.Api.Models;
using RentFlow.Api.Services.Interfaces;

namespace RentFlow.Api.Services;

/// <summary>
/// Applies allow-listed hard rules without making a landlord decision.
/// </summary>
public class DeterministicApplicationRuleTool(TimeProvider timeProvider)
    : IDeterministicApplicationRuleTool
{
    public const string ApplicationExistsRule = "ApplicationExists";
    public const string EligibleStatusRule = "ApplicationStatusEligibleForValidation";
    public const string PositiveIncomeRule = "MonthlyIncomeIsPositive";
    public const string FutureMoveInDateRule = "MoveInDateIsInFuture";
    public const string RequiredDocumentsRule = "RequiredDocumentMetadataPresent";

    public Task<DeterministicRuleValidationResult> ValidateAsync(
        RentalApplication? application,
        IReadOnlyCollection<ApplicationDocument> documents,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(documents);
        cancellationToken.ThrowIfCancellationRequested();

        var passedRules = new List<string>();
        var failedRules = new List<string>();
        var warnings = new List<string>();

        Record(application is not null, ApplicationExistsRule, passedRules, failedRules);

        if (application is null)
        {
            warnings.Add("Application-dependent rules could not be evaluated.");
        }
        else
        {
            Record(
                application.Status is RentalApplicationStatus.Submitted or RentalApplicationStatus.UnderReview,
                EligibleStatusRule,
                passedRules,
                failedRules);
            Record(application.MonthlyIncome > 0, PositiveIncomeRule, passedRules, failedRules);

            var utcToday = DateOnly.FromDateTime(timeProvider.GetUtcNow().UtcDateTime);
            Record(application.MoveInDate > utcToday, FutureMoveInDateRule, passedRules, failedRules);
        }

        var presentTypes = documents.Select(document => document.DocumentType).ToHashSet();
        Record(
            presentTypes.Contains(ApplicationDocumentType.IdentityDocument)
                && presentTypes.Contains(ApplicationDocumentType.IncomeProof),
            RequiredDocumentsRule,
            passedRules,
            failedRules);

        return Task.FromResult(new DeterministicRuleValidationResult
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
