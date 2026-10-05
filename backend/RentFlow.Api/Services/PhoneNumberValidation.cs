namespace RentFlow.Api.Services;

public static class PhoneNumberValidation
{
    // Preserve the formats and digit limits used by viewing contact disclosure.
    public static string? UsablePhoneNumber(string? value)
    {
        var phone = value?.Trim();
        if (string.IsNullOrEmpty(phone)
            || !System.Text.RegularExpressions.Regex.IsMatch(phone, @"^[+0-9][0-9\s().-]{6,31}$"))
            return null;
        var digits = phone.Count(c => c is >= '0' and <= '9');
        return digits is >= 7 and <= 15 ? phone : null;
    }
}
