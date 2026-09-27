using System.ComponentModel.DataAnnotations;

namespace RentFlow.Api.Configuration;

public sealed class PasswordResetOptions
{
    public const string SectionName = "PasswordReset";

    [Range(30, 60)]
    public int TokenLifetimeMinutes { get; init; } = 45;

    [Required]
    [Url]
    public string DevelopmentWebBaseUrl { get; init; } = "http://localhost:5173";
}
