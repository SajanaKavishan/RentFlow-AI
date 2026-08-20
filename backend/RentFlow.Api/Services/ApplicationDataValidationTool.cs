using RentFlow.Api.DTOs.ApplicationValidation;
using RentFlow.Api.Models;
using RentFlow.Api.Services.Interfaces;

namespace RentFlow.Api.Services;

/// <summary>
/// Deterministically validates required rental application data.
/// </summary>
public class ApplicationDataValidationTool(TimeProvider timeProvider) : IApplicationDataValidationTool
{
    private const int RequiredFieldCount = 6;

    public Task<ApplicationDataValidationResult> ValidateAsync(
        RentalApplication application,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(application);
        cancellationToken.ThrowIfCancellationRequested();

        var missingFields = new List<string>();
        var warnings = new List<string>();
        var validFieldCount = 0;

        CheckIdentifier(application.TenantId, nameof(application.TenantId), missingFields, ref validFieldCount);
        CheckIdentifier(application.PropertyId, nameof(application.PropertyId), missingFields, ref validFieldCount);

        var utcToday = DateOnly.FromDateTime(timeProvider.GetUtcNow().UtcDateTime);
        if (application.MoveInDate > utcToday)
        {
            validFieldCount++;
        }
        else
        {
            missingFields.Add(nameof(application.MoveInDate));
            warnings.Add("MoveInDate must be in the future.");
        }

        if (application.MonthlyIncome > 0)
        {
            validFieldCount++;
        }
        else
        {
            missingFields.Add(nameof(application.MonthlyIncome));
            warnings.Add("MonthlyIncome must be greater than zero.");
        }

        if (!string.IsNullOrWhiteSpace(application.Occupation))
        {
            validFieldCount++;
        }
        else
        {
            missingFields.Add(nameof(application.Occupation));
        }

        if (application.NumberOfOccupants >= 1)
        {
            validFieldCount++;
        }
        else
        {
            missingFields.Add(nameof(application.NumberOfOccupants));
            warnings.Add("NumberOfOccupants must be at least one.");
        }

        var completenessScore = Math.Round(
            validFieldCount * 100m / RequiredFieldCount,
            2,
            MidpointRounding.AwayFromZero);

        return Task.FromResult(new ApplicationDataValidationResult
        {
            IsValid = missingFields.Count == 0,
            CompletenessScore = completenessScore,
            MissingFields = missingFields,
            Warnings = warnings
        });
    }

    private static void CheckIdentifier(
        Guid value,
        string fieldName,
        ICollection<string> missingFields,
        ref int validFieldCount)
    {
        if (value != Guid.Empty)
        {
            validFieldCount++;
            return;
        }

        missingFields.Add(fieldName);
    }
}
