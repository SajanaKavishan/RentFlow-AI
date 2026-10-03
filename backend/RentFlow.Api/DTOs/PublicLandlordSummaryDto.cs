namespace RentFlow.Api.DTOs;

public sealed class PublicLandlordSummaryDto
{
    public string DisplayName { get; init; } = string.Empty;

    public int MemberSinceYear { get; init; }

    public bool HasProfileImage { get; init; }
}
