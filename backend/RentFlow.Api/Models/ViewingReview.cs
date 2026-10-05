namespace RentFlow.Api.Models;

public sealed class ViewingReview
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid ViewingId { get; set; }
    public Guid TenantId { get; set; }
    public Guid PropertyId { get; set; }
    public Guid LandlordId { get; set; }
    public int PropertyRating { get; set; }
    public int LandlordRating { get; set; }
    public string? Comment { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }
}
