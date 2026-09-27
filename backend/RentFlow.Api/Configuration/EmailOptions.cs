using System.ComponentModel.DataAnnotations;

namespace RentFlow.Api.Configuration;

public sealed class EmailOptions
{
    public const string SectionName = "Email";

    [Required]
    public string SmtpHost { get; init; } = string.Empty;

    [Required]
    [Range(1, 65535)]
    public int? SmtpPort { get; init; }

    [Required]
    public string Username { get; init; } = string.Empty;

    [Required]
    public string Password { get; init; } = string.Empty;

    [Required]
    [EmailAddress]
    public string FromAddress { get; init; } = string.Empty;

    [Required]
    [StringLength(200)]
    public string FromName { get; init; } = string.Empty;

    [Required]
    public bool? UseSsl { get; init; }
}
