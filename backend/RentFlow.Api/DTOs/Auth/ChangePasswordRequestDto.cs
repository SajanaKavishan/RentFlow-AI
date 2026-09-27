using System.ComponentModel.DataAnnotations;

namespace RentFlow.Api.DTOs.Auth;

public sealed class ChangePasswordRequestDto
{
    [Required]
    [StringLength(128)]
    public string CurrentPassword { get; init; } = string.Empty;

    [Required]
    [StringLength(128)]
    public string NewPassword { get; init; } = string.Empty;

    [Required]
    [StringLength(128)]
    public string NewPasswordConfirmation { get; init; } = string.Empty;
}
