using System.ComponentModel.DataAnnotations;

namespace RentFlow.Api.DTOs.Auth;

public sealed class LoginRequestDto
{
    [Required]
    [EmailAddress]
    [StringLength(320)]
    public string Email { get; init; } = string.Empty;

    [Required]
    [StringLength(128)]
    public string Password { get; init; } = string.Empty;
}
