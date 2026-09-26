using Microsoft.Extensions.Options;
using RentFlow.Api.Configuration;
using RentFlow.Api.Services;
using RentFlow.Api.Services.Interfaces;
using Xunit;

namespace RentFlow.Api.Tests.Authentication;

public sealed class SmtpEmailSenderTests
{
    [Fact]
    public void PasswordResetMessage_UsesSecurityCopyAndEncodesTheHtmlLink()
    {
        var sender = new SmtpEmailSender(Options.Create(new EmailOptions
        {
            SmtpHost = "smtp.example.test",
            SmtpPort = 587,
            Username = "test-user",
            Password = "test-password",
            FromAddress = "no-reply@example.test",
            FromName = "RentFlow AI",
            UseSsl = true
        }));
        const string resetUrl =
            "https://app.example.test/reset-password#token=token-with-<unsafe>&characters";

        var message = sender.CreateMessage(new PasswordResetEmail(
            "recipient@example.test",
            resetUrl,
            45));

        Assert.Equal("Reset your RentFlow AI password", message.Subject);
        Assert.Equal("recipient@example.test", message.To.Mailboxes.Single().Address);
        Assert.Contains("password reset was requested", message.TextBody, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("expires in 45 minutes", message.TextBody, StringComparison.Ordinal);
        Assert.Contains("ignore this email", message.TextBody, StringComparison.OrdinalIgnoreCase);
        Assert.Contains(resetUrl, message.TextBody, StringComparison.Ordinal);
        Assert.DoesNotContain("<unsafe>", message.HtmlBody, StringComparison.Ordinal);
        Assert.Contains("&lt;unsafe&gt;&amp;characters", message.HtmlBody, StringComparison.Ordinal);
    }
}
