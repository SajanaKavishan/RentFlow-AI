using RentFlow.Api.DTOs.Maintenance;
using RentFlow.Api.Models;
using RentFlow.Api.Services.Interfaces;

namespace RentFlow.Api.Services;

/// <summary>
/// Deterministically validates required maintenance request fields before coordination review.
/// </summary>
public class MaintenanceRequestDataValidationTool : IMaintenanceRequestDataValidationTool
{
    private const int RequiredFieldCount = 7;

    public Task<MaintenanceDataValidationResult> ValidateAsync(
        MaintenanceRequest? request,
        CancellationToken cancellationToken = default)
    {
        if (request is null)
        {
            throw new ArgumentNullException(nameof(request));
        }

        cancellationToken.ThrowIfCancellationRequested();

        var missingFields = new List<string>();
        var warnings = new List<string>();
        var validFieldCount = 0;

        CheckIdentifier(request.Id, nameof(request.Id), missingFields, ref validFieldCount);
        CheckIdentifier(request.PropertyId, nameof(request.PropertyId), missingFields, ref validFieldCount);
        CheckIdentifier(request.TenantId, nameof(request.TenantId), missingFields, ref validFieldCount);

        if (!string.IsNullOrWhiteSpace(request.Title))
        {
            validFieldCount++;
        }
        else
        {
            missingFields.Add(nameof(request.Title));
        }

        if (!string.IsNullOrWhiteSpace(request.Description))
        {
            validFieldCount++;
        }
        else
        {
            missingFields.Add(nameof(request.Description));
        }

        if (Enum.IsDefined(request.Category))
        {
            validFieldCount++;
        }
        else
        {
            missingFields.Add(nameof(request.Category));
            warnings.Add("A valid maintenance category is required.");
        }

        if (Enum.IsDefined(request.Priority))
        {
            validFieldCount++;
        }
        else
        {
            missingFields.Add(nameof(request.Priority));
            warnings.Add("A valid maintenance priority is required.");
        }

        var completenessScore = Math.Round(
            validFieldCount * 100m / RequiredFieldCount,
            2,
            MidpointRounding.AwayFromZero);

        return Task.FromResult(new MaintenanceDataValidationResult
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
