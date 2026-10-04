using System.ComponentModel.DataAnnotations;
using System.Text.Json.Serialization;

namespace RentFlow.Api.DTOs.ViewingReviews;

public sealed class SaveViewingReviewDto
{
    [Required, Range(1, 5), JsonNumberHandling(JsonNumberHandling.Strict)] public int? PropertyRating { get; set; }
    [Required, Range(1, 5), JsonNumberHandling(JsonNumberHandling.Strict)] public int? LandlordRating { get; set; }
    [StringLength(500)] public string? Comment { get; set; }
}

public sealed record ViewingReviewDto(Guid Id, Guid ViewingId, int PropertyRating, int LandlordRating,
    string? Comment, DateTimeOffset CreatedAt, DateTimeOffset UpdatedAt);

// Deliberately separate from the private model: no identity, viewing ID, or exact timestamps.
public sealed record PublicViewingReviewDto(int Rating, string Comment, string ReviewMonth);
public sealed record ViewingReviewSummaryDto(double? AverageRating, int ReviewCount,
    IReadOnlyList<PublicViewingReviewDto> Reviews);
