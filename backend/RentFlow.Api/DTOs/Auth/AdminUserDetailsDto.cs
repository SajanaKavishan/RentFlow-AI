using RentFlow.Api.Models;

namespace RentFlow.Api.DTOs.Auth;

public sealed record AdminUserDetailsDto(Guid Id, string FullName, string Email, string PhoneNumber,
    UserRole Role, bool IsActive, DateTimeOffset CreatedAt);
