namespace RentFlow.Api.DTOs.Auth;

public sealed record ChangePasswordResponseDto(
    string Message,
    string AccessToken,
    DateTimeOffset ExpiresAt);
