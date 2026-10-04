namespace RentFlow.Api.Models;

public enum ViewingFollowUpDecision { ApplyNow, NotNow }

/// <summary>A row is created only when a tenant atomically claims the automatic prompt.</summary>
public sealed class ViewingFollowUp
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid ViewingId { get; set; }
    public Guid TenantId { get; set; }
    public DateTimeOffset ClaimedAt { get; set; }
    public ViewingFollowUpDecision? Decision { get; set; }
    public DateTimeOffset? RespondedAt { get; set; }
}
