using System.ComponentModel.DataAnnotations;

namespace RentFlow.Api.DTOs.Auth;

public sealed class UploadProfileImageRequestDto
{
    [Required]
    public IFormFile File { get; init; } = null!;
}
