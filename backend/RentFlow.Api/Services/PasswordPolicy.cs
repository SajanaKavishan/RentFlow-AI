namespace RentFlow.Api.Services;

public static class PasswordPolicy
{
    public const int MinimumLength = 8;

    public static IReadOnlyList<string> Validate(string password)
    {
        var errors = new List<string>();

        if (password.Length < MinimumLength)
        {
            errors.Add($"Password must be at least {MinimumLength} characters long.");
        }

        if (!password.Any(char.IsUpper))
        {
            errors.Add("Password must contain an uppercase letter.");
        }

        if (!password.Any(char.IsLower))
        {
            errors.Add("Password must contain a lowercase letter.");
        }

        if (!password.Any(char.IsDigit))
        {
            errors.Add("Password must contain a number.");
        }

        if (!password.Any(character => !char.IsLetterOrDigit(character)))
        {
            errors.Add("Password must contain a non-alphanumeric character.");
        }

        return errors;
    }
}
