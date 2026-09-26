using System.Text.Json.Serialization;

namespace RentFlow.Api.DTOs.Auth;

public sealed record ForgotPasswordResponseDto(
    string Message,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    string? DevelopmentResetLink = null);
