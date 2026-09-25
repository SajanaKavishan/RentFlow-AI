namespace RentFlow.Api.Models;

public sealed class AdminBootstrapRecord
{
    public const int SingletonId = 1;

    public int Id { get; set; } = SingletonId;

    public Guid AdminUserId { get; set; }

    public DateTimeOffset CompletedAt { get; set; }
}
