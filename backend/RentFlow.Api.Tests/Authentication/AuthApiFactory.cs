using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Logging;
using RentFlow.Api.Data;

namespace RentFlow.Api.Tests.Authentication;

internal sealed class AuthApiFactory : WebApplicationFactory<Program>
{
    private readonly string _databaseName = $"AuthApiTests-{Guid.NewGuid()}";

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
        });
    }

    public HttpClient CreateHttpsClient() => CreateClient(new WebApplicationFactoryClientOptions
    {
        BaseAddress = new Uri("https://localhost")
    });
}
