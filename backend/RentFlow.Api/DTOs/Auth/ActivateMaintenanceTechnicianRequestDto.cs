using System.ComponentModel.DataAnnotations;

namespace RentFlow.Api.DTOs.Auth;

public sealed class ActivateMaintenanceTechnicianRequestDto
{
    [Required]
    [StringLength(256, MinimumLength = 32)]
    public string SetupToken { get; init; } = string.Empty;

    [Required]
    [StringLength(128, MinimumLength = 8)]
    public string Password { get; init; } = string.Empty;

    [Required]
    [StringLength(128, MinimumLength = 8)]
    public string PasswordConfirmation { get; init; } = string.Empty;
}
