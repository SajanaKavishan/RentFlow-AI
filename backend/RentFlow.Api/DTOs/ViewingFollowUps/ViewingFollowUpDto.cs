using System.ComponentModel.DataAnnotations;
using RentFlow.Api.DTOs.RentalApplications;

namespace RentFlow.Api.DTOs.ViewingFollowUps;

public sealed class ViewingFollowUpDto
{
    public Guid FollowUpId { get; set; }
    public Guid ViewingId { get; set; }
    public DateTimeOffset ClaimedAt { get; set; }
    public DateTimeOffset ClaimExpiresAt { get; set; }
    public DateTimeOffset? ViewingCompletedAt { get; set; }
    public ViewingFollowUpPropertyDto Property { get; set; } = new();
    public RentalApplicationEligibilityDto Application { get; set; } = new();
}

public sealed class ViewingFollowUpPropertyDto
{
    public Guid Id { get; set; }
    public string Title { get; set; } = string.Empty;
    public string Address { get; set; } = string.Empty;
    public string City { get; set; } = string.Empty;
}

public sealed class RespondViewingFollowUpDto
{
    [Required, RegularExpression("^(ApplyNow|NotNow)$")]
    public string Decision { get; set; } = string.Empty;
}

public sealed class ViewingFollowUpResponseDto
{
    public Guid FollowUpId { get; set; }
    public string Decision { get; set; } = string.Empty;
    public DateTimeOffset RespondedAt { get; set; }
}
