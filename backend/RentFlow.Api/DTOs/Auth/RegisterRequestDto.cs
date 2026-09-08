using System.ComponentModel.DataAnnotations;
using RentFlow.Api.Models;

namespace RentFlow.Api.DTOs.Auth;

public sealed class RegisterRequestDto
{
    [Required]
    [StringLength(200, MinimumLength = 2)]
    public string FullName { get; init; } = string.Empty;

    [Required]
    [EmailAddress]
    [StringLength(320)]
    public string Email { get; init; } = string.Empty;

    [Required]
    [StringLength(32, MinimumLength = 7)]
    public string PhoneNumber { get; init; } = string.Empty;

    [Required]
    [StringLength(128, MinimumLength = 8)]
    public string Password { get; init; } = string.Empty;

    [Required]
    public UserRole? Role { get; init; }
}
