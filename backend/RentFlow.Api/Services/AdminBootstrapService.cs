using System.Data;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Storage;
using RentFlow.Api.Data;
using RentFlow.Api.DTOs.Auth;
using RentFlow.Api.Models;

namespace RentFlow.Api.Services;

public sealed class AdminBootstrapService(
    ApplicationDbContext dbContext,
    IPasswordHasher<ApplicationUser> passwordHasher,
    TimeProvider timeProvider)
{
    public async Task<ApplicationUser> BootstrapAsync(
        string fullName,
        string email,
        string phoneNumber,
        string password,
        CancellationToken cancellationToken = default)
    {
        var request = new RegisterRequestDto
        {
            FullName = fullName,
            Email = email,
            PhoneNumber = phoneNumber,
            Password = password,
            Role = UserRole.Admin
        };
        var validationErrors = RegistrationInputValidator.Validate(request);
        if (validationErrors.Count > 0)
        {
            throw AdminBootstrapException.Validation(
                string.Join(' ', validationErrors));
        }

        var normalizedEmail = AuthService.NormalizeEmail(email);
        IDbContextTransaction? transaction = null;

        try
        {
            if (dbContext.Database.IsRelational())
            {
                transaction = await dbContext.Database.BeginTransactionAsync(
                    IsolationLevel.ReadCommitted,
                    cancellationToken);
            }

            if (await dbContext.Set<AdminBootstrapRecord>().AnyAsync(cancellationToken)
                || await dbContext.Users.AnyAsync(
                    user => user.Role == UserRole.Admin,
                    cancellationToken))
            {
                throw AdminBootstrapException.AlreadyCompleted();
            }

            if (await dbContext.Users.AnyAsync(
                user => user.NormalizedEmail == normalizedEmail,
                cancellationToken))
            {
                throw AdminBootstrapException.DuplicateEmail();
            }

            var now = timeProvider.GetUtcNow();
            var user = new ApplicationUser
            {
                Id = Guid.NewGuid(),
                FullName = fullName.Trim(),
                Email = email.Trim(),
                NormalizedEmail = normalizedEmail,
                PhoneNumber = phoneNumber.Trim(),
                Role = UserRole.Admin,
                IsActive = true,
                CreatedAt = now,
                UpdatedAt = now
            };
            user.PasswordHash = passwordHasher.HashPassword(user, password);

            dbContext.Users.Add(user);
            dbContext.Set<AdminBootstrapRecord>().Add(new AdminBootstrapRecord
            {
                Id = AdminBootstrapRecord.SingletonId,
                AdminUserId = user.Id,
                CompletedAt = now
            });

            await dbContext.SaveChangesAsync(cancellationToken);
            if (transaction is not null)
            {
                await transaction.CommitAsync(cancellationToken);
            }

            return user;
        }
        catch (DbUpdateException)
        {
            if (transaction is not null)
            {
                await transaction.RollbackAsync(cancellationToken);
                await transaction.DisposeAsync();
                transaction = null;
            }

            dbContext.ChangeTracker.Clear();
            if (await dbContext.Users.AnyAsync(
                user => user.NormalizedEmail == normalizedEmail,
                cancellationToken))
            {
                throw AdminBootstrapException.DuplicateEmail();
            }

            throw AdminBootstrapException.AlreadyCompleted();
        }
        finally
        {
            if (transaction is not null)
            {
                await transaction.DisposeAsync();
            }
        }
    }
}
