using System.Text;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.FileProviders;
using Microsoft.Extensions.Hosting;
using RentFlow.Api.Commands;
using RentFlow.Api.Data;
using RentFlow.Api.DTOs.Auth;
using RentFlow.Api.Models;
using RentFlow.Api.Services;
using RentFlow.Api.Services.Interfaces;
using Xunit;

namespace RentFlow.Api.Tests.Authentication;

public sealed class AdminBootstrapTests
{
    private const string ValidPassword = "Secure1!Password";

    [Fact]
    public async Task Command_RefusesOutsideDevelopmentBeforeReadingInput()
    {
        await using var context = CreateContext();
        var console = new RecordingConsole();
        var command = CreateCommand(context, console, Environments.Production);

        var exitCode = await command.ExecuteAsync([AdminBootstrapCommand.Option]);

        Assert.Equal(1, exitCode);
        Assert.Equal(0, console.ReadCount);
        Assert.Contains("only in Development", console.Output);
        Assert.Empty(context.Users);
        Assert.Empty(context.AdminBootstrapRecords);
    }

    [Fact]
    public async Task Bootstrap_CreatesActiveAdminWhoCanUseNormalLogin()
    {
        await using var context = CreateContext();
        var hasher = new PasswordHasher<ApplicationUser>();
        var service = CreateService(context, hasher);

        var admin = await service.BootstrapAsync(
            "Initial Admin",
            "  Admin@Example.com ",
            "+94770000000",
            ValidPassword);

        Assert.True(admin.IsActive);
        Assert.Equal(UserRole.Admin, admin.Role);
        Assert.Equal("ADMIN@EXAMPLE.COM", admin.NormalizedEmail);
        Assert.Single(context.AdminBootstrapRecords);

        var authService = new AuthService(
            context,
            hasher,
            new StubJwtTokenService(),
            TimeProvider.System);
        var login = await authService.LoginAsync(new LoginRequestDto
        {
            Email = "admin@example.com",
            Password = ValidPassword
        });

        Assert.Equal(admin.Id, login.User.Id);
        Assert.Equal(UserRole.Admin, login.User.Role);
        Assert.Equal("test-token", login.AccessToken);
    }

    [Fact]
    public async Task Bootstrap_ValidatesPasswordAndStoresOnlyItsHash()
    {
        await using var context = CreateContext();
        var hasher = new PasswordHasher<ApplicationUser>();
        var service = CreateService(context, hasher);

        var exception = await Assert.ThrowsAsync<AdminBootstrapException>(() =>
            service.BootstrapAsync(
                "Initial Admin",
                "admin@example.com",
                "+94770000000",
                "alllowercase"));

        Assert.Equal(AdminBootstrapError.Validation, exception.Error);
        Assert.Empty(context.Users);
        Assert.Empty(context.AdminBootstrapRecords);

        var admin = await service.BootstrapAsync(
            "Initial Admin",
            "admin@example.com",
            "+94770000000",
            ValidPassword);

        Assert.NotEqual(ValidPassword, admin.PasswordHash);
        Assert.DoesNotContain(ValidPassword, admin.PasswordHash, StringComparison.Ordinal);
        Assert.NotEqual(
            PasswordVerificationResult.Failed,
            hasher.VerifyHashedPassword(admin, admin.PasswordHash, ValidPassword));
    }

    [Fact]
    public async Task Bootstrap_RejectsDuplicateEmailWithoutChangingExistingUser()
    {
        await using var context = CreateContext();
        var existing = new ApplicationUser
        {
            Id = Guid.NewGuid(),
            FullName = "Existing Tenant",
            Email = "person@example.com",
            NormalizedEmail = "PERSON@EXAMPLE.COM",
            PhoneNumber = "+94771111111",
            PasswordHash = "existing-hash",
            Role = UserRole.Tenant,
            IsActive = true,
            CreatedAt = DateTimeOffset.UtcNow,
            UpdatedAt = DateTimeOffset.UtcNow
        };
        context.Users.Add(existing);
        await context.SaveChangesAsync();
        var service = CreateService(context);

        var exception = await Assert.ThrowsAsync<AdminBootstrapException>(() =>
            service.BootstrapAsync(
                "Initial Admin",
                " PERSON@example.com ",
                "+94770000000",
                ValidPassword));

        Assert.Equal(AdminBootstrapError.DuplicateEmail, exception.Error);
        Assert.Same(existing, Assert.Single(context.Users));
        Assert.Empty(context.AdminBootstrapRecords);
    }

    [Fact]
    public async Task Bootstrap_RejectsRepeatWithoutOverwritingAdmin()
    {
        await using var context = CreateContext();
        var service = CreateService(context);
        var original = await service.BootstrapAsync(
            "Initial Admin",
            "admin@example.com",
            "+94770000000",
            ValidPassword);
        var originalHash = original.PasswordHash;

        var exception = await Assert.ThrowsAsync<AdminBootstrapException>(() =>
            service.BootstrapAsync(
                "Replacement Admin",
                "replacement@example.com",
                "+94772222222",
                "Different2!Password"));

        Assert.Equal(AdminBootstrapError.AlreadyCompleted, exception.Error);
        var stored = Assert.Single(context.Users);
        Assert.Equal(original.Id, stored.Id);
        Assert.Equal(originalHash, stored.PasswordHash);
        Assert.Single(context.AdminBootstrapRecords);
    }

    [Fact]
    public async Task Command_DoesNotWriteCredentialsHashesOrTokens()
    {
        await using var context = CreateContext();
        var console = new RecordingConsole(
            lines: ["Initial Admin", "admin@example.com", "+94770000000"],
            secrets: [ValidPassword, ValidPassword]);
        var command = CreateCommand(context, console, Environments.Development);

        var exitCode = await command.ExecuteAsync([AdminBootstrapCommand.Option]);

        Assert.Equal(0, exitCode);
        Assert.Contains("created successfully", console.Output);
        Assert.DoesNotContain(ValidPassword, console.Output, StringComparison.Ordinal);
        Assert.DoesNotContain("admin@example.com", console.Output, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("hash", console.Output, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("token", console.Output, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain(context.Users.Single().PasswordHash, console.Output, StringComparison.Ordinal);
    }

    [Fact]
    public async Task Command_RejectsCredentialArgumentsWithoutEchoingThem()
    {
        await using var context = CreateContext();
        var console = new RecordingConsole();
        var command = CreateCommand(context, console, Environments.Development);

        var exitCode = await command.ExecuteAsync(
            [AdminBootstrapCommand.Option, ValidPassword]);

        Assert.Equal(2, exitCode);
        Assert.Equal(0, console.ReadCount);
        Assert.DoesNotContain(ValidPassword, console.Output, StringComparison.Ordinal);
        Assert.Empty(context.Users);
    }

    private static ApplicationDbContext CreateContext()
    {
        var options = new DbContextOptionsBuilder<ApplicationDbContext>()
            .UseInMemoryDatabase($"AdminBootstrapTests-{Guid.NewGuid()}")
            .Options;
        return new ApplicationDbContext(options);
    }

    private static AdminBootstrapService CreateService(
        ApplicationDbContext context,
        IPasswordHasher<ApplicationUser>? hasher = null) =>
        new(context, hasher ?? new PasswordHasher<ApplicationUser>(), TimeProvider.System);

    private static AdminBootstrapCommand CreateCommand(
        ApplicationDbContext context,
        IAdminBootstrapConsole console,
        string environmentName) =>
        new(
            new TestHostEnvironment(environmentName),
            console,
            CreateService(context));

    private sealed class StubJwtTokenService : IJwtTokenService
    {
        public JwtToken CreateToken(ApplicationUser user) =>
            new("test-token", DateTimeOffset.UtcNow.AddMinutes(15));
    }

    private sealed class TestHostEnvironment(string environmentName) : IHostEnvironment
    {
        public string EnvironmentName { get; set; } = environmentName;
        public string ApplicationName { get; set; } = "RentFlow.Api.Tests";
        public string ContentRootPath { get; set; } = AppContext.BaseDirectory;
        public IFileProvider ContentRootFileProvider { get; set; } = new NullFileProvider();
    }

    private sealed class RecordingConsole(
        IEnumerable<string>? lines = null,
        IEnumerable<string>? secrets = null) : IAdminBootstrapConsole
    {
        private readonly Queue<string> _lines = new(lines ?? []);
        private readonly Queue<string> _secrets = new(secrets ?? []);
        private readonly StringBuilder _output = new();

        public bool IsInputInteractive { get; init; } = true;

        public int ReadCount { get; private set; }

        public string Output => _output.ToString();

        public string? ReadLine()
        {
            ReadCount++;
            return _lines.Count == 0 ? null : _lines.Dequeue();
        }

        public string ReadSecret()
        {
            ReadCount++;
            return _secrets.Count == 0 ? string.Empty : _secrets.Dequeue();
        }

        public void Write(string value) => _output.Append(value);

        public void WriteLine(string value) => _output.AppendLine(value);
    }
}
