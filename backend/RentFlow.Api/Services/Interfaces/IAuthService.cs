using RentFlow.Api.DTOs.Auth;

namespace RentFlow.Api.Services.Interfaces;

public interface IAuthService
{
    Task<AuthResponseDto> RegisterAsync(
        RegisterRequestDto request,
        CancellationToken cancellationToken = default);

    Task<AuthResponseDto> LoginAsync(
        LoginRequestDto request,
        CancellationToken cancellationToken = default);

    Task<UserProfileDto?> GetUserAsync(
        Guid userId,
        CancellationToken cancellationToken = default);
}
