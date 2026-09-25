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

public sealed class PasswordResetService(
    ApplicationDbContext dbContext,
    IPasswordHasher<ApplicationUser> passwordHasher,
    IOptions<PasswordResetOptions> options,
    IHostEnvironment environment,
    TimeProvider timeProvider)
{
    public const string GenericRequestMessage =
        "If an account exists, password reset instructions have been created.";

    private readonly PasswordResetOptions _options = options.Value;

    public async Task<ForgotPasswordResponseDto> RequestAsync(
        ForgotPasswordRequestDto request,
        CancellationToken cancellationToken = default)
    {
        var validationErrors = ValidateDataAnnotations(request);
        if (validationErrors.Count > 0)
        {
            throw PasswordResetException.Validation(string.Join(' ', validationErrors));
        }

        var now = timeProvider.GetUtcNow();
        var rawToken = WebEncoders.Base64UrlEncode(RandomNumberGenerator.GetBytes(32));
        var normalizedEmail = AuthService.NormalizeEmail(request.Email);
        var user = await dbContext.Users.SingleOrDefaultAsync(
            candidate => candidate.NormalizedEmail == normalizedEmail
                && candidate.IsActive
                && candidate.PasswordHash != null,
            cancellationToken);

        if (user is not null)
        {
            var outstandingTokens = await dbContext.PasswordResetTokens
                .Where(token => token.UserId == user.Id && token.ConsumedAt == null)
                .ToListAsync(cancellationToken);
            foreach (var outstandingToken in outstandingTokens)
            {
                outstandingToken.ConsumedAt = now;
            }

            dbContext.PasswordResetTokens.Add(new PasswordResetToken
            {
                Id = Guid.NewGuid(),
                UserId = user.Id,
                TokenDigest = ComputeTokenDigest(rawToken),
                CreatedAt = now,
                ExpiresAt = now.AddMinutes(_options.TokenLifetimeMinutes)
            });

            try
            {
                await dbContext.SaveChangesAsync(cancellationToken);
            }
            catch (DbUpdateException)
            {
                throw PasswordResetException.Persistence();
            }
        }

        return new ForgotPasswordResponseDto(
            GenericRequestMessage,
            environment.IsDevelopment() ? CreateDevelopmentResetLink(rawToken) : null);
    }

    public async Task<ResetPasswordResponseDto> ResetAsync(
        ResetPasswordRequestDto request,
        CancellationToken cancellationToken = default)
    {
        var validationErrors = ValidateDataAnnotations(request).ToList();
        if (!string.IsNullOrEmpty(request.NewPassword))
        {
            validationErrors.AddRange(PasswordPolicy.Validate(request.NewPassword));
        }
        if (!string.Equals(
                request.NewPassword,
                request.NewPasswordConfirmation,
                StringComparison.Ordinal))
        {
            validationErrors.Add("New password and confirmation must match.");
        }
        if (validationErrors.Count > 0)
        {
            throw PasswordResetException.Validation(
                string.Join(' ', validationErrors.Distinct(StringComparer.Ordinal)));
        }

        var digest = ComputeTokenDigest(request.Token);
        await using var transaction = dbContext.Database.IsRelational()
            ? await dbContext.Database.BeginTransactionAsync(cancellationToken)
            : null;

        var resetToken = await dbContext.PasswordResetTokens.SingleOrDefaultAsync(
            candidate => candidate.TokenDigest == digest,
            cancellationToken);
        if (resetToken is null)
        {
            throw PasswordResetException.InvalidOrExpiredToken();
        }

        var now = timeProvider.GetUtcNow();
        var user = await dbContext.Users.SingleOrDefaultAsync(
            candidate => candidate.Id == resetToken.UserId,
            cancellationToken);
        if (resetToken.ConsumedAt is not null
            || resetToken.ExpiresAt <= now
            || user is null
            || !user.IsActive
            || string.IsNullOrEmpty(user.PasswordHash))
        {
            throw PasswordResetException.InvalidOrExpiredToken();
        }

        var outstandingTokens = await dbContext.PasswordResetTokens
            .Where(token => token.UserId == user.Id && token.ConsumedAt == null)
            .ToListAsync(cancellationToken);
        foreach (var outstandingToken in outstandingTokens)
        {
            outstandingToken.ConsumedAt = now;
        }

        user.PasswordHash = passwordHasher.HashPassword(user, request.NewPassword);
        user.TokenVersion = checked(user.TokenVersion + 1);
        user.UpdatedAt = now;
        await NotificationDeliveryPolicy.QueueAsync(
            dbContext,
            NotificationEventFactory.ForPasswordReset(user, now),
            cancellationToken);

        try
        {
            await dbContext.SaveChangesAsync(cancellationToken);
            if (transaction is not null)
            {
                await transaction.CommitAsync(cancellationToken);
            }
        }
        catch (DbUpdateConcurrencyException)
        {
            throw PasswordResetException.InvalidOrExpiredToken();
        }
        catch (DbUpdateException)
        {
            throw PasswordResetException.Persistence();
        }

        return new ResetPasswordResponseDto("Your password was reset successfully.");
    }

    private string CreateDevelopmentResetLink(string rawToken) =>
        $"{_options.DevelopmentWebBaseUrl.TrimEnd('/')}/reset-password#token={Uri.EscapeDataString(rawToken)}";

    internal static string ComputeTokenDigest(string token) =>
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
