using System.ComponentModel.DataAnnotations;
using RentFlow.Api.DTOs.Auth;

namespace RentFlow.Api.Services;

public static class RegistrationInputValidator
{
    public static IReadOnlyList<string> Validate(RegisterRequestDto request)
    {
        var validationResults = new List<ValidationResult>();
        Validator.TryValidateObject(
            request,
            new ValidationContext(request),
            validationResults,
            validateAllProperties: true);

        return validationResults
            .Select(result => result.ErrorMessage)
            .Where(message => !string.IsNullOrWhiteSpace(message))
            .Cast<string>()
            .Concat(PasswordPolicy.Validate(request.Password))
            .Distinct(StringComparer.Ordinal)
            .ToArray();
    }
}
