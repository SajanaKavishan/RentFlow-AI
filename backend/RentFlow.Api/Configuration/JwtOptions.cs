using System.ComponentModel.DataAnnotations;

namespace RentFlow.Api.Configuration;

public sealed class JwtOptions
{
    public const string SectionName = "Jwt";
    public const string SigningKeyKey = SectionName + ":SigningKey";

    [Required]
    public string Issuer { get; init; } = string.Empty;

    [Required]
    public string Audience { get; init; } = string.Empty;

    [Required]
    public string SigningKey { get; init; } = string.Empty;

    [Range(1, 1440)]
    public int ExpiryMinutes { get; init; } = 30;
}
