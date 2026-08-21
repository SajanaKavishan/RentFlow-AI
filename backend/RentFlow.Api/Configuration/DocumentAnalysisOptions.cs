using System.ComponentModel.DataAnnotations;

namespace RentFlow.Api.Configuration;

public sealed class DocumentAnalysisOptions
{
    public const string SectionName = "DocumentAnalysis";
    public const long UploadLimitBytes = 5 * 1024 * 1024;

    public bool Enabled { get; init; } = true;

    [Range(1, UploadLimitBytes)]
    public long MaxFileBytes { get; init; } = UploadLimitBytes;

    [Required]
    [MinLength(1)]
    public string[] AllowedContentTypes { get; init; } =
    [
        "application/pdf",
        "image/jpeg",
        "image/png"
    ];
}
