using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using System.ComponentModel.DataAnnotations;
using RentFlow.Api.Data;
using RentFlow.Api.DTOs.Auth;
using RentFlow.Api.Models;
using RentFlow.Api.Services.Interfaces;

namespace RentFlow.Api.Services;

public sealed class AuthService(
    ApplicationDbContext dbContext,
    IPasswordHasher<ApplicationUser> passwordHasher,
    IJwtTokenService jwtTokenService,
    IFileStorageService fileStorageService,
    TimeProvider timeProvider,
    ILogger<AuthService> logger) : IAuthService
{
    private const long MaximumProfileImageBytes = 5 * 1024 * 1024;
    private static readonly IReadOnlyDictionary<string, string> AllowedProfileImageTypes =
        new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            ["image/jpeg"] = "jpg",
            ["image/png"] = "png",
            ["image/webp"] = "webp"
        };

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
        var user = await dbContext.Users
            .Include(candidate => candidate.ProfileImage)
            .SingleOrDefaultAsync(
            candidate => candidate.NormalizedEmail == normalizedEmail,
            cancellationToken);

        var passwordHash = user?.PasswordHash;
        if (user is null || !user.IsActive || string.IsNullOrEmpty(passwordHash))
        {
            throw AuthServiceException.InvalidCredentials();
        }

        var verification = passwordHasher.VerifyHashedPassword(
            user,
            passwordHash,
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
                user.Role,
                user.ProfileImage != null))
            .SingleOrDefaultAsync(cancellationToken);
    }

    public async Task<UserProfileDto?> UpdateProfileAsync(
        Guid userId,
        UpdateProfileRequestDto request,
        CancellationToken cancellationToken = default)
    {
        var validationResults = new List<ValidationResult>();
        if (!Validator.TryValidateObject(request, new ValidationContext(request), validationResults, true))
        {
            throw AuthServiceException.Validation(string.Join(' ', validationResults
                .Select(result => result.ErrorMessage)
                .Where(message => !string.IsNullOrWhiteSpace(message))));
        }

        var user = await dbContext.Users
            .Include(candidate => candidate.ProfileImage)
            .SingleOrDefaultAsync(candidate => candidate.Id == userId && candidate.IsActive, cancellationToken);
        if (user is null) return null;

        user.FullName = request.FullName.Trim();
        user.PhoneNumber = request.PhoneNumber.Trim();
        user.UpdatedAt = timeProvider.GetUtcNow();
        await dbContext.SaveChangesAsync(cancellationToken);
        return ToProfile(user);
    }

    public async Task<UserProfileDto?> UploadProfileImageAsync(
        Guid userId,
        byte[] content,
        string contentType,
        CancellationToken cancellationToken = default)
    {
        var normalizedType = contentType.Trim().ToLowerInvariant();
        if (content.Length == 0 || content.LongLength > MaximumProfileImageBytes)
        {
            throw AuthServiceException.Validation("The profile image must be between 1 byte and 5 MB.");
        }
        if (!AllowedProfileImageTypes.TryGetValue(normalizedType, out var extension)
            || !HasValidImageSignature(content, normalizedType))
        {
            throw AuthServiceException.Validation("Only valid JPEG, PNG, and WEBP profile images are supported.");
        }

        var user = await dbContext.Users
            .Include(candidate => candidate.ProfileImage)
            .SingleOrDefaultAsync(candidate => candidate.Id == userId && candidate.IsActive, cancellationToken);
        if (user is null) return null;

        var oldStorageKey = user.ProfileImage?.StorageKey;
        var storageKey = $"users/{userId:N}/profile/{Guid.NewGuid():N}.{extension}";
        await using var stream = new MemoryStream(content, writable: false);
        await fileStorageService.UploadAsync(stream, storageKey, normalizedType, cancellationToken);

        try
        {
            var now = timeProvider.GetUtcNow();
            if (user.ProfileImage is null)
            {
                user.ProfileImage = new UserProfileImage
                {
                    UserId = user.Id,
                    StorageKey = storageKey,
                    ContentType = normalizedType,
                    FileSizeBytes = content.LongLength,
                    UpdatedAt = now
                };
            }
            else
            {
                user.ProfileImage.StorageKey = storageKey;
                user.ProfileImage.ContentType = normalizedType;
                user.ProfileImage.FileSizeBytes = content.LongLength;
                user.ProfileImage.UpdatedAt = now;
            }
            user.UpdatedAt = now;
            await dbContext.SaveChangesAsync(cancellationToken);
        }
        catch
        {
            await TryDeleteImageAsync(storageKey);
            throw;
        }

        if (!string.IsNullOrEmpty(oldStorageKey) && oldStorageKey != storageKey)
        {
            await TryDeleteImageAsync(oldStorageKey);
        }
        return ToProfile(user);
    }

    public async Task<UserProfileImageContentDto?> GetProfileImageAsync(
        Guid userId,
        CancellationToken cancellationToken = default)
    {
        var image = await dbContext.UserProfileImages
            .AsNoTracking()
            .Where(candidate => candidate.UserId == userId && candidate.User.IsActive)
            .Select(candidate => new { candidate.StorageKey, candidate.ContentType, candidate.FileSizeBytes })
            .SingleOrDefaultAsync(cancellationToken);
        if (image is null) return null;

        var content = await fileStorageService.DownloadBytesAsync(
            image.StorageKey,
            MaximumProfileImageBytes,
            cancellationToken);
        if (content.LongLength != image.FileSizeBytes)
        {
            throw new InvalidOperationException("The stored profile image did not match its metadata.");
        }
        return new UserProfileImageContentDto(content, image.ContentType);
    }

    public static string NormalizeEmail(string email) =>
        email.Trim().ToUpperInvariant();

    private AuthResponseDto CreateAuthResponse(ApplicationUser user)
    {
        var token = jwtTokenService.CreateToken(user);
        return new AuthResponseDto(token.Value, token.ExpiresAt, ToProfile(user));
    }

    private static UserProfileDto ToProfile(ApplicationUser user) =>
        new(user.Id, user.FullName, user.Email, user.PhoneNumber, user.Role, user.ProfileImage is not null);

    private static bool HasValidImageSignature(byte[] content, string contentType) => contentType switch
    {
        "image/jpeg" => content.Length >= 3 && content[0] == 0xFF && content[1] == 0xD8 && content[2] == 0xFF,
        "image/png" => content.Length >= 8 && content.AsSpan(0, 8).SequenceEqual(new byte[] { 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A }),
        "image/webp" => content.Length >= 12
            && content.AsSpan(0, 4).SequenceEqual("RIFF"u8)
            && content.AsSpan(8, 4).SequenceEqual("WEBP"u8),
        _ => false
    };

    private async Task TryDeleteImageAsync(string storageKey)
    {
        try
        {
            await fileStorageService.DeleteAsync(storageKey);
        }
        catch (Exception exception)
        {
            logger.LogWarning(exception, "Unable to remove replaced profile image object {StorageKey}.", storageKey);
        }
    }
}
