using RentFlow.Api.Models;

namespace RentFlow.Api.DTOs.Auth;

public sealed record MaintenanceTechnicianProvisioningResponseDto(
    Guid Id,
    string FullName,
    string Email,
    string PhoneNumber,
    UserRole Role,
    bool IsActive,
    string PasswordSetupToken,
    DateTimeOffset PasswordSetupExpiresAt);
