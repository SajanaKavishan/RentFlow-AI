using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;
using Microsoft.Extensions.Logging.Abstractions;
using RentFlow.Api.Data;
using RentFlow.Api.Models;
using RentFlow.Api.Services;
using RentFlow.Api.Services.Interfaces;
using Xunit;

namespace RentFlow.Api.Tests.Services;

public class MaintenanceAttachmentServiceTests
{
    [Fact]
    public async Task UploadAsync_StoresMetadataAfterSuccessfulPrivateUpload()
    {
        await using var context = CreateContext();
        var request = await AddRequestAsync(context);
        var storage = new FakeFileStorageService();

        var result = await UploadAsync(
            CreateService(context, storage),
            request);

        Assert.Equal("photo.jpg", result.FileName);
        Assert.Single(storage.UploadCalls);

        var attachment =
            await context.MaintenanceAttachments.SingleAsync();

        Assert.StartsWith(
            $"maintenance-requests/{request.Id:N}/",
            attachment.StorageKey);

        Assert.DoesNotContain(
            attachment.StorageKey,
            result.FileName);

        Assert.Equal(
            request.TenantId,
            attachment.UploadedByUserId);
    }

    [Fact]
    public async Task UploadAsync_RejectsEmptyFile()
    {
        await using var context = CreateContext();
        var request = await AddRequestAsync(context);

        var exception =
            await Assert.ThrowsAsync<MaintenanceRequestServiceException>(
                () => UploadAsync(
                    CreateService(
                        context,
                        new FakeFileStorageService()),
                    request,
                    size: 0));

        Assert.Equal(
            MaintenanceRequestServiceError.Validation,
            exception.Error);
    }

    [Fact]
    public async Task UploadAsync_RejectsUnsupportedType()
    {
        await using var context = CreateContext();
        var request = await AddRequestAsync(context);

        var exception =
            await Assert.ThrowsAsync<MaintenanceRequestServiceException>(
                () => UploadAsync(
                    CreateService(
                        context,
                        new FakeFileStorageService()),
                    request,
                    contentType: "application/pdf"));

        Assert.Equal(
            MaintenanceRequestServiceError.Validation,
            exception.Error);
    }

    [Fact]
    public async Task UploadAsync_RejectsOversizedFile()
    {
        await using var context = CreateContext();
        var request = await AddRequestAsync(context);

        var exception =
            await Assert.ThrowsAsync<MaintenanceRequestServiceException>(
                () => UploadAsync(
                    CreateService(
                        context,
                        new FakeFileStorageService()),
                    request,
                    size: (10 * 1024 * 1024) + 1));

        Assert.Equal(
            MaintenanceRequestServiceError.Validation,
            exception.Error);
    }

    [Fact]
    public async Task UploadAsync_RejectsWrongTenant()
    {
        await using var context = CreateContext();
        var request = await AddRequestAsync(context);

        var exception =
            await Assert.ThrowsAsync<MaintenanceRequestServiceException>(
                () => UploadAsync(
                    CreateService(
                        context,
                        new FakeFileStorageService()),
                    request,
                    tenantId: Guid.NewGuid()));

        Assert.Equal(
            MaintenanceRequestServiceError.NotFound,
            exception.Error);

        Assert.Empty(context.MaintenanceAttachments);
    }

    [Fact]
    public async Task UploadAsync_WhenStorageFails_CreatesNoMetadata()
    {
        await using var context = CreateContext();
        var request = await AddRequestAsync(context);

        var storage = new FakeFileStorageService
        {
            UploadException =
                new InvalidOperationException(
                    "R2 unavailable")
        };

        await Assert.ThrowsAsync<InvalidOperationException>(
            () => UploadAsync(
                CreateService(context, storage),
                request));

        Assert.Empty(context.MaintenanceAttachments);
    }

    [Fact]
    public async Task GetByRequestAsync_ReturnsSafeMetadata()
    {
        await using var context = CreateContext();
        var request = await AddRequestAsync(context);

        context.MaintenanceAttachments.Add(
            CreateAttachment(request));

        await context.SaveChangesAsync();

        var result =
            await CreateService(
                    context,
                    new FakeFileStorageService())
                .GetByRequestAsync(
                    request.Id,
                    request.TenantId);

        Assert.Single(result);
        Assert.Equal(
            "photo.jpg",
            result[0].FileName);
    }

    [Fact]
    public async Task GenerateDownloadUrlAsync_RejectsAttachmentFromAnotherRequest()
    {
        await using var context = CreateContext();

        var request =
            await AddRequestAsync(context);

        var other =
            await AddRequestAsync(
                context,
                request.TenantId);

        var attachment =
            CreateAttachment(other);

        context.MaintenanceAttachments.Add(
            attachment);

        await context.SaveChangesAsync();

        var exception =
            await Assert.ThrowsAsync<MaintenanceRequestServiceException>(
                () => CreateService(
                        context,
                        new FakeFileStorageService())
                    .GenerateDownloadUrlAsync(
                        request.Id,
                        attachment.Id,
                        request.TenantId));

        Assert.Equal(
            MaintenanceRequestServiceError.NotFound,
            exception.Error);
    }

    [Fact]
    public async Task DeleteAsync_RemovesMetadataAndPrivateObject()
    {
        await using var context = CreateContext();

        var request =
            await AddRequestAsync(context);

        var attachment =
            CreateAttachment(request);

        context.MaintenanceAttachments.Add(
            attachment);

        await context.SaveChangesAsync();

        var storage =
            new FakeFileStorageService();

        await CreateService(
                context,
                storage)
            .DeleteAsync(
                request.Id,
                attachment.Id,
                request.TenantId);

        Assert.Empty(
            context.MaintenanceAttachments);

        Assert.Equal(
            "test-key",
            Assert.Single(storage.DeleteCalls));
    }

    private static MaintenanceAttachmentService CreateService(
        ApplicationDbContext context,
        IFileStorageService storage) =>
        new(
            context,
            storage,
            NullLogger<MaintenanceAttachmentService>.Instance);

    private static Task<
        RentFlow.Api.DTOs.Maintenance.MaintenanceAttachmentResponseDto>
        UploadAsync(
            MaintenanceAttachmentService service,
            MaintenanceRequest request,
            string contentType = "image/jpeg",
            long size = 1,
            Guid? tenantId = null) =>
        service.UploadAsync(
            request.Id,
            tenantId ?? request.TenantId,
            new MemoryStream([1]),
            "unsafe/path/photo.jpg",
            contentType,
            size,
            "before",
            default);

    private static async Task<MaintenanceRequest> AddRequestAsync(
        ApplicationDbContext context,
        Guid? tenantId = null)
    {
        var request = new MaintenanceRequest
        {
            Id = Guid.NewGuid(),
            TenantId =
                tenantId ?? Guid.NewGuid(),
            PropertyId = Guid.NewGuid(),
            Title = "Leak",
            Description = "Tap leak",
            Category =
                MaintenanceCategory.Plumbing,
            CreatedAt =
                DateTimeOffset.UtcNow
        };

        context.MaintenanceRequests.Add(
            request);

        await context.SaveChangesAsync();

        return request;
    }

    private static MaintenanceAttachment CreateAttachment(
        MaintenanceRequest request) =>
        new()
        {
            Id = Guid.NewGuid(),
            MaintenanceRequestId =
                request.Id,
            StorageKey =
                "test-key",
            FileName =
                "photo.jpg",
            ContentType =
                "image/jpeg",
            FileSize =
                1,
            UploadedByUserId =
                request.TenantId,
            CreatedAt =
                DateTimeOffset.UtcNow
        };

    private static ApplicationDbContext CreateContext() =>
        new(
            new DbContextOptionsBuilder<ApplicationDbContext>()
                .UseInMemoryDatabase(
                    $"MaintenanceAttachmentTests-{Guid.NewGuid()}")
                .ConfigureWarnings(
                    x => x.Ignore(
                        InMemoryEventId.TransactionIgnoredWarning))
                .Options);

    private sealed class FakeFileStorageService
        : IFileStorageService
    {
        public List<string> UploadCalls { get; } = [];

        public List<string> DeleteCalls { get; } = [];

        public Exception? UploadException { get; init; }

        public Task UploadAsync(
            Stream content,
            string storageKey,
            string contentType,
            CancellationToken cancellationToken = default)
        {
            UploadCalls.Add(storageKey);

            return UploadException is null
                ? Task.CompletedTask
                : Task.FromException(UploadException);
        }

        public Task DeleteAsync(
            string storageKey,
            CancellationToken cancellationToken = default)
        {
            DeleteCalls.Add(storageKey);

            return Task.CompletedTask;
        }

        public Task<byte[]> DownloadBytesAsync(
            string storageKey,
            long maximumBytes,
            CancellationToken cancellationToken = default)
        {
            return Task.FromResult(
                Array.Empty<byte>());
        }

        public Task<string> GenerateDownloadUrlAsync(
            string storageKey,
            string originalFileName,
            string contentType,
            TimeSpan lifetime)
        {
            return Task.FromResult(
                "https://downloads.invalid/attachment");
        }

        public Task<string> GenerateInlineUrlAsync(
            string storageKey,
            string contentType,
            TimeSpan lifetime)
        {
            return Task.FromResult(
                $"https://downloads.invalid/inline/{storageKey}");
        }
    }
}