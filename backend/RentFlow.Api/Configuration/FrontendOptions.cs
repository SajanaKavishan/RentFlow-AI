using System.ComponentModel.DataAnnotations;

namespace RentFlow.Api.Configuration;

public sealed class FrontendOptions : IValidatableObject
{
    public const string SectionName = "Frontend";
    public const string BaseUrlKey = SectionName + ":BaseUrl";

    [Required]
    public string BaseUrl { get; init; } = string.Empty;

    public IEnumerable<ValidationResult> Validate(ValidationContext validationContext)
    {
        if (!Uri.TryCreate(BaseUrl, UriKind.Absolute, out var uri)
            || (uri.Scheme != Uri.UriSchemeHttps && uri.Scheme != Uri.UriSchemeHttp)
            || !string.IsNullOrEmpty(uri.Query)
            || !string.IsNullOrEmpty(uri.Fragment))
        {
            yield return new ValidationResult(
                "Frontend:BaseUrl must be an absolute HTTP or HTTPS URL without a query or fragment.",
                [nameof(BaseUrl)]);
        }
    }
}
