using System.ComponentModel.DataAnnotations;
using System.Security.Cryptography;
using System.Text;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.WebUtilities;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using RentFlow.Api.Configuration;
using RentFlow.Api.Data;
using RentFlow.Api.DTOs.Auth;
using RentFlow.Api.Models;

namespace RentFlow.Api.Services;

public sealed class TechnicianProvisioningService(
    ApplicationDbContext dbContext,
    IPasswordHasher<ApplicationUser> passwordHasher,
    IOptions<StaffProvisioningOptions> options,
    TimeProvider timeProvider)
{
    private readonly StaffProvisioningOptions _options = options.Value;

    public async Task<MaintenanceTechnicianProvisioningResponseDto> CreatePendingAsync(
        Guid adminUserId,
        CreateMaintenanceTechnicianRequestDto request,
        CancellationToken cancellationToken = default)
    {
        var validationErrors = ValidateDataAnnotations(request);
        if (validationErrors.Count > 0)
        {
            throw TechnicianProvisioningException.Validation(
                string.Join(' ', validationErrors));
        }

        if (!await IsActiveAdminAsync(adminUserId, cancellationToken))
        {
            throw TechnicianProvisioningException.Forbidden();
        }

        var normalizedEmail = AuthService.NormalizeEmail(request.Email);
        if (await dbContext.Users.AnyAsync(
                user => user.NormalizedEmail == normalizedEmail,
                cancellationToken))
        {
            throw TechnicianProvisioningException.DuplicateEmail();
        }

        var now = timeProvider.GetUtcNow();
        var rawToken = WebEncoders.Base64UrlEncode(RandomNumberGenerator.GetBytes(32));
        var user = new ApplicationUser
        {
            Id = Guid.NewGuid(),
            FullName = request.FullName.Trim(),
            Email = request.Email.Trim(),
            NormalizedEmail = normalizedEmail,
            PhoneNumber = request.PhoneNumber.Trim(),
            PasswordHash = null,
            Role = UserRole.MaintenanceTechnician,
            IsActive = false,
            CreatedAt = now,
            UpdatedAt = now
        };
        var setupToken = new TechnicianPasswordSetupToken
        {
            Id = Guid.NewGuid(),
            UserId = user.Id,
            CreatedByAdminId = adminUserId,
            TokenDigest = ComputeTokenDigest(rawToken),
            CreatedAt = now,
            ExpiresAt = now.AddMinutes(_options.SetupTokenLifetimeMinutes)
        };

        dbContext.Users.Add(user);
        dbContext.TechnicianPasswordSetupTokens.Add(setupToken);

        try
        {
            await dbContext.SaveChangesAsync(cancellationToken);
        }
        catch (DbUpdateException)
        {
            dbContext.ChangeTracker.Clear();
            if (await dbContext.Users.AnyAsync(
                    candidate => candidate.NormalizedEmail == normalizedEmail,
                    cancellationToken))
            {
                throw TechnicianProvisioningException.DuplicateEmail();
            }

            throw TechnicianProvisioningException.Persistence();
        }

        return new MaintenanceTechnicianProvisioningResponseDto(
            user.Id,
            user.FullName,
            user.Email,
            user.PhoneNumber,
            user.Role,
            user.IsActive,
            rawToken,
            setupToken.ExpiresAt);
    }

    public async Task ActivateAsync(
        ActivateMaintenanceTechnicianRequestDto request,
        CancellationToken cancellationToken = default)
    {
        var validationErrors = ValidateDataAnnotations(request).ToList();
        if (!string.IsNullOrEmpty(request.Password))
        {
            validationErrors.AddRange(PasswordPolicy.Validate(request.Password));
        }

        if (!string.Equals(
                request.Password,
                request.PasswordConfirmation,
                StringComparison.Ordinal))
        {
            validationErrors.Add("Password confirmation does not match.");
        }

        if (validationErrors.Count > 0)
        {
            throw TechnicianProvisioningException.Validation(
                string.Join(' ', validationErrors.Distinct(StringComparer.Ordinal)));
        }

        var digest = ComputeTokenDigest(request.SetupToken);
        var setupToken = await dbContext.TechnicianPasswordSetupTokens
            .SingleOrDefaultAsync(
                candidate => candidate.TokenDigest == digest,
                cancellationToken);
        if (setupToken is null)
        {
            throw TechnicianProvisioningException.InvalidOrExpiredToken();
        }

        var now = timeProvider.GetUtcNow();
        var user = await dbContext.Users.SingleOrDefaultAsync(
            candidate => candidate.Id == setupToken.UserId,
            cancellationToken);
        if (setupToken.ConsumedAt is not null
            || setupToken.ExpiresAt <= now
            || user is null
            || user.IsActive
            || user.Role != UserRole.MaintenanceTechnician
            || !string.IsNullOrEmpty(user.PasswordHash))
        {
            throw TechnicianProvisioningException.InvalidOrExpiredToken();
        }

        user.PasswordHash = passwordHasher.HashPassword(user, request.Password);
        user.IsActive = true;
        user.UpdatedAt = now;
        setupToken.ConsumedAt = now;

        await using var transaction = dbContext.Database.IsRelational()
            ? await dbContext.Database.BeginTransactionAsync(cancellationToken)
            : null;

        try
        {
            await dbContext.SaveChangesAsync(cancellationToken);
            dbContext.Notifications.Add(
                NotificationEventFactory.ForMaintenanceTechnicianActivation(
                    user,
                    setupToken.CreatedByAdminId,
                    now));
            await dbContext.SaveChangesAsync(cancellationToken);
            if (transaction is not null)
            {
                await transaction.CommitAsync(cancellationToken);
            }
        }
        catch (DbUpdateConcurrencyException)
        {
            throw TechnicianProvisioningException.InvalidOrExpiredToken();
        }
        catch (DbUpdateException)
        {
            throw TechnicianProvisioningException.Persistence();
        }
    }

    private Task<bool> IsActiveAdminAsync(
        Guid userId,
        CancellationToken cancellationToken) =>
        dbContext.Users.AsNoTracking().AnyAsync(
            user => user.Id == userId
                && user.IsActive
                && user.Role == UserRole.Admin,
            cancellationToken);

    private static string ComputeTokenDigest(string token) =>
        Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(token)));

    private static IReadOnlyList<string> ValidateDataAnnotations(object request)
    {
        var results = new List<ValidationResult>();
        Validator.TryValidateObject(
            request,
            new ValidationContext(request),
            results,
            validateAllProperties: true);
        return results
            .Select(result => result.ErrorMessage)
            .Where(message => !string.IsNullOrWhiteSpace(message))
            .Cast<string>()
            .ToArray();
    }
}
