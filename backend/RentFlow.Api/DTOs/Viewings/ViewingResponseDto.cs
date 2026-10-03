using RentFlow.Api.Models;

namespace RentFlow.Api.DTOs.Viewings;

/// <summary>
/// Represents viewing request data returned by the API.
/// </summary>
public class ViewingResponseDto
{
    public Guid Id { get; set; }

    public Guid TenantId { get; set; }

    public ViewingTenantSummaryDto Tenant { get; set; } = new();

    public Guid PropertyId { get; set; }

    public DateTimeOffset RequestedDateTime { get; set; }
    public int? DurationMinutes { get; set; }
    public string? TimeZoneId { get; set; }
    public string? RequestedLocalDate { get; set; }
    public string? RequestedDisplayTime { get; set; }

    public ViewingStatus Status { get; set; }

    /// <summary>Server cancellation eligibility at the time of this response.</summary>
    public bool CanCancel { get; set; }

    /// <summary>Inclusive cancellation deadline for Approved viewings only.</summary>
    public DateTimeOffset? CancellationDeadline { get; set; }

    public string? TenantMessage { get; set; }

    public string? LandlordResponse { get; set; }

    public DateTimeOffset CreatedAt { get; set; }

    public DateTimeOffset? UpdatedAt { get; set; }
}
