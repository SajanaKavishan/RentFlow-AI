using System.ComponentModel.DataAnnotations;

namespace RentFlow.Api.DTOs.Auth;

public sealed class ResetPasswordRequestDto
{
    [Required]
    [StringLength(256, MinimumLength = 32)]
    public string Token { get; init; } = string.Empty;

    [Required]
    [StringLength(128, MinimumLength = 8)]
    public string NewPassword { get; init; } = string.Empty;

    [Required]
    [StringLength(128, MinimumLength = 8)]
    public string NewPasswordConfirmation { get; init; } = string.Empty;
}
