namespace RentFlow.Api.DTOs.Auth;

public sealed record AuthResponseDto(
    string AccessToken,
    DateTimeOffset ExpiresAt,
    UserProfileDto User);
