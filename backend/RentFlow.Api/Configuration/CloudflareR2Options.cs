using System.ComponentModel.DataAnnotations;

namespace RentFlow.Api.Configuration;

/// <summary>
/// Configuration required to access a private Cloudflare R2 bucket.
/// </summary>
public sealed class CloudflareR2Options
{
    public const string SectionName = "CloudflareR2";

    [Required]
    public string AccountId { get; set; } = string.Empty;

    [Required]
    public string AccessKeyId { get; set; } = string.Empty;

    [Required]
    public string SecretAccessKey { get; set; } = string.Empty;

    [Required]
    public string BucketName { get; set; } = string.Empty;
}
