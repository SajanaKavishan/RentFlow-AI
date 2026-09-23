using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using RentFlow.Api.Data;
using RentFlow.Api.DTOs.Auth;
using RentFlow.Api.Models;
using RentFlow.Api.Services.Interfaces;

namespace RentFlow.Api.Services;

public sealed class AuthService(
    ApplicationDbContext dbContext,
    IPasswordHasher<ApplicationUser> passwordHasher,
    IJwtTokenService jwtTokenService,
    TimeProvider timeProvider) : IAuthService
{
    public async Task<AuthResponseDto> RegisterAsync(
        RegisterRequestDto request,
        CancellationToken cancellationToken = default)
    {
        var role = request.Role;
        if (role is not (UserRole.Tenant or UserRole.Landlord))
        {
            throw AuthServiceException.Validation(
                "Public registration is limited to Tenant and Landlord roles.");
        }

        var validationErrors = RegistrationInputValidator.Validate(request);
        if (validationErrors.Count > 0)
        {
            throw AuthServiceException.Validation(string.Join(' ', validationErrors));
        }

        var normalizedEmail = NormalizeEmail(request.Email);
        if (await dbContext.Users.AnyAsync(
                user => user.NormalizedEmail == normalizedEmail,
                cancellationToken))
        {
            throw AuthServiceException.DuplicateEmail();
        }

        var now = timeProvider.GetUtcNow();
        var user = new ApplicationUser
        {
            Id = Guid.NewGuid(),
            FullName = request.FullName.Trim(),
            Email = request.Email.Trim(),
            NormalizedEmail = normalizedEmail,
            PhoneNumber = request.PhoneNumber.Trim(),
            Role = role.Value,
            IsActive = true,
            CreatedAt = now,
            UpdatedAt = now
        };
        user.PasswordHash = passwordHasher.HashPassword(user, request.Password);

        dbContext.Users.Add(user);

        try
        {
            await dbContext.SaveChangesAsync(cancellationToken);
        }
        catch (DbUpdateException)
        {
            throw AuthServiceException.DuplicateEmail();
        }

        return CreateAuthResponse(user);
    }

    public async Task<AuthResponseDto> LoginAsync(
        LoginRequestDto request,
        CancellationToken cancellationToken = default)
    {
        var normalizedEmail = NormalizeEmail(request.Email);
        var user = await dbContext.Users.SingleOrDefaultAsync(
            candidate => candidate.NormalizedEmail == normalizedEmail,
            cancellationToken);

        if (user is null || !user.IsActive)
        {
            throw AuthServiceException.InvalidCredentials();
        }

        var verification = passwordHasher.VerifyHashedPassword(
            user,
            user.PasswordHash,
            request.Password);
        if (verification == PasswordVerificationResult.Failed)
        {
            throw AuthServiceException.InvalidCredentials();
        }

        if (verification == PasswordVerificationResult.SuccessRehashNeeded)
        {
            user.PasswordHash = passwordHasher.HashPassword(user, request.Password);
            user.UpdatedAt = timeProvider.GetUtcNow();
            await dbContext.SaveChangesAsync(cancellationToken);
        }

        return CreateAuthResponse(user);
    }

    public async Task<UserProfileDto?> GetUserAsync(
        Guid userId,
        CancellationToken cancellationToken = default)
    {
        return await dbContext.Users
            .AsNoTracking()
            .Where(user => user.Id == userId && user.IsActive)
            .Select(user => new UserProfileDto(
                user.Id,
                user.FullName,
                user.Email,
                user.PhoneNumber,
                user.Role))
            .SingleOrDefaultAsync(cancellationToken);
    }

    public static string NormalizeEmail(string email) =>
        email.Trim().ToUpperInvariant();

    private AuthResponseDto CreateAuthResponse(ApplicationUser user)
    {
        var token = jwtTokenService.CreateToken(user);
        return new AuthResponseDto(token.Value, token.ExpiresAt, ToProfile(user));
    }

    private static UserProfileDto ToProfile(ApplicationUser user) =>
        new(user.Id, user.FullName, user.Email, user.PhoneNumber, user.Role);
}
