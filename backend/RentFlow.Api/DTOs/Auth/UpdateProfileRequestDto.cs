using System.ComponentModel.DataAnnotations;

namespace RentFlow.Api.DTOs.Auth;

public sealed class UpdateProfileRequestDto
{
    [Required]
    [StringLength(200, MinimumLength = 2)]
    public string FullName { get; init; } = string.Empty;

    [Required]
    [StringLength(32, MinimumLength = 7)]
    [RegularExpression(@"^[+\d][\d\s().-]{6,31}$", ErrorMessage = "Enter a valid phone number.")]
    public string PhoneNumber { get; init; } = string.Empty;
}
