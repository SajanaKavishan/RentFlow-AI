namespace RentFlow.Api.Models;

public sealed class ApplicationUser
{
    public Guid Id { get; set; }

    public string FullName { get; set; } = string.Empty;

    public string Email { get; set; } = string.Empty;

    public string NormalizedEmail { get; set; } = string.Empty;

    public string PhoneNumber { get; set; } = string.Empty;

    public string? PasswordHash { get; set; }

    public UserRole Role { get; set; }

    public bool IsActive { get; set; } = true;

    public DateTimeOffset CreatedAt { get; set; }

    public DateTimeOffset UpdatedAt { get; set; }

    public UserProfileImage? ProfileImage { get; set; }
}
