using System.ComponentModel.DataAnnotations;

namespace RentFlow.Api.DTOs.Auth;

public sealed class CreateMaintenanceTechnicianRequestDto
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
}
