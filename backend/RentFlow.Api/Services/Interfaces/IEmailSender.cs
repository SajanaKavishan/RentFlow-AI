namespace RentFlow.Api.Services.Interfaces;

public sealed record PasswordResetEmail(
    string RecipientAddress,
    string ResetUrl,
    int TokenLifetimeMinutes);

public interface IEmailSender
{
    Task SendPasswordResetEmailAsync(
        PasswordResetEmail email,
        CancellationToken cancellationToken = default);
}
