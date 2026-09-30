namespace RentFlow.Api.Models;

public sealed class TenantPropertyFavorite
{
    public Guid TenantId { get; set; }

    public Guid PropertyId { get; set; }

    public DateTimeOffset CreatedAt { get; set; }
}
