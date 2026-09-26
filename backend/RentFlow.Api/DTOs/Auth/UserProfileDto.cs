using RentFlow.Api.Models;

namespace RentFlow.Api.DTOs.Auth;

public sealed record UserProfileDto(
    Guid Id,
    string FullName,
    string Email,
    string PhoneNumber,
    UserRole Role,
    bool HasProfileImage);
