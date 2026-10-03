using System.ComponentModel.DataAnnotations;
using RentFlow.Api.Models;

namespace RentFlow.Api.Services;

public static class PropertyListingPreferenceValidator
{
    public static IEnumerable<ValidationResult> Validate(
        PetPolicyStatus? petPolicy,
        string? petPolicyNotes,
        IEnumerable<string>? includedUtilities)
    {
        var notes = petPolicyNotes?.Trim();
        if (petPolicy == PetPolicyStatus.Conditional && string.IsNullOrWhiteSpace(notes))
        {
            yield return new ValidationResult(
                "Pet notes are required when the pet policy is Conditional.",
                ["PetPolicyNotes"]);
        }

        if (petPolicy == PetPolicyStatus.NotAllowed && !string.IsNullOrWhiteSpace(notes))
        {
            yield return new ValidationResult(
                "Pet notes must be empty when pets are not allowed.",
                ["PetPolicyNotes"]);
        }

        if (!PropertyListingCatalog.UtilitiesAreValid(includedUtilities))
        {
            yield return new ValidationResult(
                "Included utilities must use approved canonical keys.",
                ["IncludedUtilities"]);
        }
    }
}
