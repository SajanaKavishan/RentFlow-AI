using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Logging;
using System.Collections.Concurrent;
using RentFlow.Api.Data;
using RentFlow.Api.DTOs.ApplicationValidation;
using RentFlow.Api.Models;
using RentFlow.Api.Services.Interfaces;

namespace RentFlow.Api.Tests.Authentication;

internal sealed class AuthApiFactory : WebApplicationFactory<Program>
{
    private readonly string _databaseName = $"AuthApiTests-{Guid.NewGuid()}";
    private readonly TimeProvider? _timeProvider;
    private readonly string _environmentName;

    public AuthApiFactory(
        TimeProvider? timeProvider = null,
        string environmentName = "Testing")
    {
        _timeProvider = timeProvider;
        _environmentName = environmentName;
    }

    public RecordingFileStorageService FileStorage { get; } = new();

    public RecordingValidationOrchestrator ValidationOrchestrator { get; } = new();

    public RecordingEmailSender EmailSender { get; } = new();

    public RecordingLoggerProvider Logs { get; } = new();

    public IPropertyMatchingAgentClient? PropertyMatchingAgentClient { get; init; }

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment(_environmentName);
        builder.ConfigureLogging(logging =>
        {
            logging.ClearProviders();
            logging.AddProvider(Logs);
        });
        builder.ConfigureAppConfiguration((_, configuration) =>
        {
            configuration.AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["Jwt:Issuer"] = "RentFlow.Api.Tests",
                ["Jwt:Audience"] = "RentFlow.TestClients",
                ["Jwt:SigningKey"] = "test-only-signing-key-that-is-at-least-32-bytes-long",
                ["Jwt:ExpiryMinutes"] = "15",
                ["StaffProvisioning:SetupTokenLifetimeMinutes"] = "60",
                ["PasswordReset:TokenLifetimeMinutes"] = "45",
                ["PasswordReset:DevelopmentWebBaseUrl"] = "https://web.example.test",
                ["Email:SmtpHost"] = "smtp.example.test",
                ["Email:SmtpPort"] = "587",
                ["Email:Username"] = "test-user",
                ["Email:Password"] = "test-password",
                ["Email:FromAddress"] = "no-reply@example.test",
                ["Email:FromName"] = "RentFlow AI",
                ["Email:UseSsl"] = "true",
                ["Frontend:BaseUrl"] = "https://app.example.test",
                ["CloudflareR2:AccountId"] = "test-account",
                ["CloudflareR2:AccessKeyId"] = "test-access-key",
                ["CloudflareR2:SecretAccessKey"] = "test-secret-key",
                ["CloudflareR2:BucketName"] = "test-bucket"
            });
        });

        builder.ConfigureServices(services =>
        {
            services.RemoveAll<ApplicationDbContext>();
            services.RemoveAll<DbContextOptions<ApplicationDbContext>>();

            var providerConfigurations = services
                .Where(descriptor =>
                    descriptor.ServiceType.IsGenericType &&
                    descriptor.ServiceType.GetGenericTypeDefinition().Name
                        == "IDbContextOptionsConfiguration`1")
                .ToArray();

            foreach (var descriptor in providerConfigurations)
            {
                services.Remove(descriptor);
            }

            services.AddDbContext<ApplicationDbContext>(options =>
                options.UseInMemoryDatabase(_databaseName));

            services.AddDataProtection()
                .UseEphemeralDataProtectionProvider();

            if (_timeProvider is not null)
            {
                services.RemoveAll<TimeProvider>();
                services.AddSingleton(_timeProvider);
            }

            services.RemoveAll<IFileStorageService>();
            services.AddSingleton<IFileStorageService>(FileStorage);

            services.RemoveAll<IApplicationValidationOrchestrator>();
            services.AddSingleton<IApplicationValidationOrchestrator>(
                ValidationOrchestrator);

            services.RemoveAll<IEmailSender>();
            services.AddSingleton<IEmailSender>(EmailSender);

            if (PropertyMatchingAgentClient is not null)
            {
                services.RemoveAll<IPropertyMatchingAgentClient>();
                services.AddSingleton(PropertyMatchingAgentClient);
            }
        });
    }

    public HttpClient CreateHttpsClient(bool allowAutoRedirect = true) =>
        CreateClient(new WebApplicationFactoryClientOptions
    {
        BaseAddress = new Uri("https://localhost"),
        AllowAutoRedirect = allowAutoRedirect
    });

    public void EnsureActiveUser(Guid userId, UserRole role)
    {
        using var scope = Services.CreateScope();
        var context = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
        if (context.Users.Any(user => user.Id == userId))
        {
            return;
        }

        var now = DateTimeOffset.UtcNow;
        context.Users.Add(new ApplicationUser
        {
            Id = userId,
            FullName = $"Test {role}",
            Email = $"{userId:N}@example.test",
            NormalizedEmail = $"{userId:N}@EXAMPLE.TEST",
            PhoneNumber = "+94770000000",
            Role = role,
            IsActive = true,
            TokenVersion = 0,
            CreatedAt = now,
            UpdatedAt = now
        });
        context.SaveChanges();
    }
}

internal sealed class RecordingEmailSender : IEmailSender
{
    private readonly ConcurrentQueue<PasswordResetEmail> _messages = new();

    public IReadOnlyList<PasswordResetEmail> Messages => _messages.ToArray();

    public Exception? Failure { get; set; }

    public Task SendPasswordResetEmailAsync(
        PasswordResetEmail email,
        CancellationToken cancellationToken = default)
    {
        _messages.Enqueue(email);
        return Failure is null
            ? Task.CompletedTask
            : Task.FromException(Failure);
    }
}

internal sealed class RecordingLoggerProvider : ILoggerProvider
{
    private readonly ConcurrentQueue<string> _messages = new();

    public IReadOnlyCollection<string> Messages => _messages.ToArray();

    public ILogger CreateLogger(string categoryName) => new RecordingLogger(_messages);

    public void Dispose()
    {
    }

    private sealed class RecordingLogger(ConcurrentQueue<string> messages) : ILogger
    {
        public IDisposable? BeginScope<TState>(TState state) where TState : notnull => null;

        public bool IsEnabled(LogLevel logLevel) => true;

        public void Log<TState>(
            LogLevel logLevel,
            EventId eventId,
            TState state,
            Exception? exception,
            Func<TState, Exception?, string> formatter)
        {
            messages.Enqueue(formatter(state, exception));
        }
    }
}

internal sealed class RecordingFileStorageService : IFileStorageService
{
    private readonly Dictionary<string, byte[]> _objects =
        new(StringComparer.Ordinal);

    public int DownloadUrlCalls { get; private set; }

    public async Task UploadAsync(
        Stream content,
        string storageKey,
        string contentType,
        CancellationToken cancellationToken = default)
    {
        await using var buffer = new MemoryStream();
        await content.CopyToAsync(buffer, cancellationToken);
        _objects[storageKey] = buffer.ToArray();
    }

    public Task DeleteAsync(
        string storageKey,
        CancellationToken cancellationToken = default)
    {
        _objects.Remove(storageKey);
        return Task.CompletedTask;
    }

    public Task<byte[]> DownloadBytesAsync(
        string storageKey,
        long maximumBytes,
        CancellationToken cancellationToken = default)
    {
        return Task.FromResult(
            _objects.TryGetValue(storageKey, out var content)
                ? content
                : Array.Empty<byte>());
    }

    public Task<string> GenerateDownloadUrlAsync(
        string storageKey,
        string originalFileName,
        string contentType,
        TimeSpan lifetime)
    {
        DownloadUrlCalls++;
        return Task.FromResult(
            "https://signed.example.test/document");
    }

    public Task<string> GenerateInlineUrlAsync(
        string storageKey,
        string contentType,
        TimeSpan lifetime)
    {
        return Task.FromResult(
            $"https://signed.example.test/inline/{storageKey}");
    }
}

internal sealed class RecordingValidationOrchestrator
    : IApplicationValidationOrchestrator
{
    public int Calls { get; private set; }

    public Task<ApplicationValidationWorkflowResponseDto> StartValidationAsync(
        Guid applicationId,
        CancellationToken cancellationToken = default)
    {
        Calls++;

        return Task.FromResult(
            new ApplicationValidationWorkflowResponseDto
            {
                Id = Guid.NewGuid(),
                ApplicationId = applicationId,
                Objective = "Validate application for landlord review.",
                Status =
                    ApplicationValidationWorkflowStatus.AwaitingHumanReview,
                RequiresHumanApproval = true,
                CreatedAt = DateTimeOffset.UtcNow,
                UpdatedAt = DateTimeOffset.UtcNow
            });
    }
}
