using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Logging;
using RentFlow.Api.Data;
using RentFlow.Api.DTOs.ApplicationValidation;
using RentFlow.Api.Models;
using RentFlow.Api.Services.Interfaces;

namespace RentFlow.Api.Tests.Authentication;

internal sealed class AuthApiFactory : WebApplicationFactory<Program>
{
    private readonly string _databaseName = $"AuthApiTests-{Guid.NewGuid()}";
    private readonly TimeProvider? _timeProvider;

    public AuthApiFactory(TimeProvider? timeProvider = null)
    {
        _timeProvider = timeProvider;
    }

    public RecordingFileStorageService FileStorage { get; } = new();

    public RecordingValidationOrchestrator ValidationOrchestrator { get; } = new();

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Testing");
        builder.ConfigureLogging(logging => logging.ClearProviders());
        builder.ConfigureAppConfiguration((_, configuration) =>
        {
            configuration.AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["Jwt:Issuer"] = "RentFlow.Api.Tests",
                ["Jwt:Audience"] = "RentFlow.TestClients",
                ["Jwt:SigningKey"] = "test-only-signing-key-that-is-at-least-32-bytes-long",
                ["Jwt:ExpiryMinutes"] = "15",
                ["StaffProvisioning:SetupTokenLifetimeMinutes"] = "60",
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
                .Where(descriptor => descriptor.ServiceType.IsGenericType
                    && descriptor.ServiceType.GetGenericTypeDefinition().Name
                        == "IDbContextOptionsConfiguration`1")
                .ToArray();
            foreach (var descriptor in providerConfigurations)
            {
                services.Remove(descriptor);
            }
            services.AddDbContext<ApplicationDbContext>(options =>
                options.UseInMemoryDatabase(_databaseName));
            services.AddDataProtection().UseEphemeralDataProtectionProvider();
            if (_timeProvider is not null)
            {
                services.RemoveAll<TimeProvider>();
                services.AddSingleton(_timeProvider);
            }
            services.RemoveAll<IFileStorageService>();
            services.AddSingleton<IFileStorageService>(FileStorage);
            services.RemoveAll<IApplicationValidationOrchestrator>();
            services.AddSingleton<IApplicationValidationOrchestrator>(ValidationOrchestrator);
        });
    }

    public HttpClient CreateHttpsClient(bool allowAutoRedirect = true) =>
        CreateClient(new WebApplicationFactoryClientOptions
    {
        BaseAddress = new Uri("https://localhost"),
        AllowAutoRedirect = allowAutoRedirect
    });
}

internal sealed class RecordingFileStorageService : IFileStorageService
{
    public int DownloadUrlCalls { get; private set; }

    public Task UploadAsync(Stream content, string storageKey, string contentType,
        CancellationToken cancellationToken = default) => Task.CompletedTask;

    public Task DeleteAsync(string storageKey,
        CancellationToken cancellationToken = default) => Task.CompletedTask;

    public Task<byte[]> DownloadBytesAsync(string storageKey, long maximumBytes,
        CancellationToken cancellationToken = default) => Task.FromResult(Array.Empty<byte>());

    public Task<string> GenerateDownloadUrlAsync(string storageKey, string originalFileName,
        string contentType, TimeSpan lifetime)
    {
        DownloadUrlCalls++;
        return Task.FromResult("https://signed.example.test/document");
    }
}

internal sealed class RecordingValidationOrchestrator : IApplicationValidationOrchestrator
{
    public int Calls { get; private set; }

    public Task<ApplicationValidationWorkflowResponseDto> StartValidationAsync(
        Guid applicationId,
        CancellationToken cancellationToken = default)
    {
        Calls++;
        return Task.FromResult(new ApplicationValidationWorkflowResponseDto
        {
            Id = Guid.NewGuid(),
            ApplicationId = applicationId,
            Objective = "Validate application for landlord review.",
            Status = ApplicationValidationWorkflowStatus.AwaitingHumanReview,
            RequiresHumanApproval = true,
            CreatedAt = DateTimeOffset.UtcNow,
            UpdatedAt = DateTimeOffset.UtcNow
        });
    }
}
