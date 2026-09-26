using System.ComponentModel.DataAnnotations;

namespace RentFlow.Api.DTOs.Auth;

public sealed class ForgotPasswordRequestDto
{
    [Required]
    [EmailAddress]
    [StringLength(320)]
    public string Email { get; init; } = string.Empty;
}
