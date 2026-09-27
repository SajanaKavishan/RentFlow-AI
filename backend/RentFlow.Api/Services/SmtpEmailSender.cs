using System.Text.Encodings.Web;
using MailKit.Net.Smtp;
using MailKit.Security;
using Microsoft.Extensions.Options;
using MimeKit;
using RentFlow.Api.Configuration;
using RentFlow.Api.Services.Interfaces;

namespace RentFlow.Api.Services;

public sealed class SmtpEmailSender(IOptions<EmailOptions> options) : IEmailSender
{
    private readonly EmailOptions _options = options.Value;

    public async Task SendPasswordResetEmailAsync(
        PasswordResetEmail email,
        CancellationToken cancellationToken = default)
    {
        var message = CreateMessage(email);
        var secureSocketOptions = _options.UseSsl!.Value
            ? _options.SmtpPort == 465
                ? SecureSocketOptions.SslOnConnect
                : SecureSocketOptions.StartTls
            : SecureSocketOptions.None;

        using var client = new SmtpClient();
        await client.ConnectAsync(
            _options.SmtpHost,
            _options.SmtpPort!.Value,
            secureSocketOptions,
            cancellationToken);
        await client.AuthenticateAsync(
            _options.Username,
            _options.Password,
            cancellationToken);
        await client.SendAsync(message, cancellationToken);
        await client.DisconnectAsync(quit: true, cancellationToken);
    }

    internal MimeMessage CreateMessage(PasswordResetEmail email)
    {
        var encodedResetUrl = HtmlEncoder.Default.Encode(email.ResetUrl);
        var message = new MimeMessage
        {
            Subject = "Reset your RentFlow AI password",
            Body = new BodyBuilder
            {
                TextBody = $"""
                    A password reset was requested for your RentFlow AI account.

                    Reset your password:
                    {email.ResetUrl}

                    This link expires in {email.TokenLifetimeMinutes} minutes.

                    If you did not request this password reset, you may safely ignore this email.
                    """,
                HtmlBody = $"""
                    <p>A password reset was requested for your RentFlow AI account.</p>
                    <p><a href="{encodedResetUrl}">Reset your password</a></p>
                    <p>This link expires in {email.TokenLifetimeMinutes} minutes.</p>
                    <p>If you did not request this password reset, you may safely ignore this email.</p>
                    """
            }.ToMessageBody()
        };
        message.From.Add(new MailboxAddress(_options.FromName, _options.FromAddress));
        message.To.Add(new MailboxAddress(string.Empty, email.RecipientAddress));
        return message;
    }
}
