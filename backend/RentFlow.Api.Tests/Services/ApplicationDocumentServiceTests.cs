using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;
using Microsoft.Extensions.Logging.Abstractions;
using RentFlow.Api.Data;
using RentFlow.Api.DTOs.ApplicationDocuments;
using RentFlow.Api.Models;
using RentFlow.Api.Services;
using RentFlow.Api.Services.Interfaces;
using Xunit;

namespace RentFlow.Api.Tests.Services;

public class ApplicationDocumentServiceTests
{
    private static readonly Guid TenantId = Guid.Parse("11111111-1111-1111-1111-111111111111");
    private static readonly Guid OtherTenantId = Guid.Parse("22222222-2222-2222-2222-222222222222");
    private static readonly Guid ApplicationId = Guid.Parse("33333333-3333-3333-3333-333333333333");
    private static readonly Guid OtherApplicationId = Guid.Parse("44444444-4444-4444-4444-444444444444");
    private static readonly Guid DocumentId = Guid.Parse("55555555-5555-5555-5555-555555555555");
    private static readonly Guid OtherDocumentId = Guid.Parse("66666666-6666-6666-6666-666666666666");
    private static readonly Guid PropertyId = Guid.Parse("77777777-7777-7777-7777-777777777777");
    private static readonly DateTimeOffset CreatedAt = new(2026, 8, 18, 9, 0, 0, TimeSpan.Zero);
    private static readonly DateTimeOffset UploadedAt = new(2026, 8, 18, 10, 0, 0, TimeSpan.Zero);

    [Fact]
    public async Task UploadAsync_SucceedsForOwnerWithDraftApplication()
    {
        await using var context = CreateContext();
        AddApplication(context, RentalApplicationStatus.Draft);
        await context.SaveChangesAsync();
        var storage = new FakeFileStorageService();
        var service = CreateService(context, storage);

        var result = await UploadAsync(service, "application/pdf");

        Assert.Equal(ApplicationId, result.ApplicationId);
        Assert.Equal("application/pdf", result.ContentType);
        Assert.Equal(TimeSpan.Zero, result.UploadedAt.Offset);
        Assert.Single(storage.UploadCalls);
    }

    [Fact]
    public async Task UploadAsync_SucceedsForChangesRequestedApplication()
    {
        await using var context = CreateContext();
        AddApplication(context, RentalApplicationStatus.ChangesRequested);
        await context.SaveChangesAsync();
        var storage = new FakeFileStorageService();
        var service = CreateService(context, storage);

        var result = await UploadAsync(service, "image/jpeg");

        Assert.Equal(ApplicationId, result.ApplicationId);
        Assert.Equal("image/jpeg", result.ContentType);
        Assert.Single(storage.UploadCalls);
    }

    [Fact]
    public async Task UploadAsync_RejectsEmptyFile()
    {
        await using var context = CreateContext();
        var storage = new FakeFileStorageService();
        var service = CreateService(context, storage);

        var exception = await Assert.ThrowsAsync<ApplicationDocumentServiceException>(() =>
            UploadAsync(service, fileSizeBytes: 0));

        Assert.Equal(ApplicationDocumentServiceError.Validation, exception.Error);
        Assert.Empty(storage.UploadCalls);
    }

    [Fact]
    public async Task UploadAsync_RejectsFileLargerThanFiveMegabytes()
    {
        await using var context = CreateContext();
        var storage = new FakeFileStorageService();
        var service = CreateService(context, storage);

        var exception = await Assert.ThrowsAsync<ApplicationDocumentServiceException>(() =>
            UploadAsync(service, fileSizeBytes: (5 * 1024 * 1024) + 1));

        Assert.Equal(ApplicationDocumentServiceError.Validation, exception.Error);
        Assert.Empty(storage.UploadCalls);
    }

    [Fact]
    public async Task UploadAsync_RejectsUnsupportedContentType()
    {
        await using var context = CreateContext();
        var storage = new FakeFileStorageService();
        var service = CreateService(context, storage);

        var exception = await Assert.ThrowsAsync<ApplicationDocumentServiceException>(() =>
            UploadAsync(service, "text/plain"));

        Assert.Equal(ApplicationDocumentServiceError.Validation, exception.Error);
        Assert.Empty(storage.UploadCalls);
    }

    [Fact]
    public async Task UploadAsync_RejectsTenantOwnershipMismatch()
    {
        await using var context = CreateContext();
        AddApplication(context, RentalApplicationStatus.Draft);
        await context.SaveChangesAsync();
        var storage = new FakeFileStorageService();
        var service = CreateService(context, storage);

        var exception = await Assert.ThrowsAsync<ApplicationDocumentServiceException>(() =>
            UploadAsync(service, tenantId: OtherTenantId));

        Assert.Equal(ApplicationDocumentServiceError.NotFound, exception.Error);
        Assert.Empty(storage.UploadCalls);
    }

    [Fact]
    public async Task UploadAsync_RejectsSubmittedApplication()
    {
        await using var context = CreateContext();
        AddApplication(context, RentalApplicationStatus.Submitted);
        await context.SaveChangesAsync();
        var storage = new FakeFileStorageService();
        var service = CreateService(context, storage);

        var exception = await Assert.ThrowsAsync<ApplicationDocumentServiceException>(() =>
            UploadAsync(service));

        Assert.Equal(ApplicationDocumentServiceError.Conflict, exception.Error);
        Assert.Empty(storage.UploadCalls);
    }

    [Fact]
    public async Task UploadAsync_RejectsApprovedApplication()
    {
        await using var context = CreateContext();
        AddApplication(context, RentalApplicationStatus.Approved);
        await context.SaveChangesAsync();
        var storage = new FakeFileStorageService();
        var service = CreateService(context, storage);

        var exception = await Assert.ThrowsAsync<ApplicationDocumentServiceException>(() =>
            UploadAsync(service));

        Assert.Equal(ApplicationDocumentServiceError.Conflict, exception.Error);
        Assert.Empty(storage.UploadCalls);
    }

    [Fact]
    public async Task UploadAsync_PersistsDocumentMetadata()
    {
        await using var context = CreateContext();
        AddApplication(context, RentalApplicationStatus.Draft);
        await context.SaveChangesAsync();
        var storage = new FakeFileStorageService();
        var service = CreateService(context, storage);

        var result = await UploadAsync(
            service,
            contentType: "image/png",
            originalFileName: @"C:\uploads\income.png",
            fileSizeBytes: 128);

        var stored = await context.ApplicationDocuments.SingleAsync();
        Assert.Equal(result.Id, stored.Id);
        Assert.Equal(ApplicationId, stored.ApplicationId);
        Assert.Equal(ApplicationDocumentType.IncomeProof, stored.DocumentType);
        Assert.Equal("income.png", stored.OriginalFileName);
        Assert.Equal("image/png", stored.ContentType);
        Assert.Equal(128, stored.FileSizeBytes);
        Assert.Equal(TimeSpan.Zero, stored.UploadedAt.Offset);
    }

    [Fact]
    public async Task UploadAsync_WhenStorageUploadFails_DoesNotPersistMetadata()
    {
        await using var context = CreateContext();
        AddApplication(context, RentalApplicationStatus.Draft);
        await context.SaveChangesAsync();
        var storage = new FakeFileStorageService
        {
            UploadException = new InvalidOperationException("Simulated storage failure.")
        };
        var service = CreateService(context, storage);

        await Assert.ThrowsAsync<InvalidOperationException>(() => UploadAsync(service));

        Assert.Empty(context.ApplicationDocuments);
        Assert.Single(storage.UploadCalls);
        Assert.Empty(storage.DeleteCalls);
    }

    [Fact]
    public async Task UploadAsync_WhenDatabasePersistenceFails_AttemptsStorageCleanup()
    {
        await using var context = CreateFailingContext();
        AddApplication(context, RentalApplicationStatus.Draft);
        await context.SaveChangesAsync();
        context.FailNextSave = true;
        var storage = new FakeFileStorageService();
        var service = CreateService(context, storage);

        await Assert.ThrowsAsync<DbUpdateException>(() => UploadAsync(service));

        var upload = Assert.Single(storage.UploadCalls);
        var cleanup = Assert.Single(storage.DeleteCalls);
        Assert.Equal(upload.StorageKey, cleanup.StorageKey);
        Assert.Empty(await context.ApplicationDocuments.AsNoTracking().ToListAsync());
    }

    [Fact]
    public async Task GetByApplicationAsync_ReturnsOnlyDocumentsForOwnedApplication()
    {
        await using var context = CreateContext();
        AddApplication(context, RentalApplicationStatus.Draft);
        AddApplication(
            context,
            RentalApplicationStatus.Draft,
            OtherApplicationId,
            TenantId);
        AddDocument(context, DocumentId, ApplicationId, UploadedAt);
        AddDocument(context, OtherDocumentId, OtherApplicationId, UploadedAt.AddMinutes(1));
        await context.SaveChangesAsync();
        var service = CreateService(context, new FakeFileStorageService());

        var results = await service.GetByApplicationAsync(ApplicationId, TenantId);

        var result = Assert.Single(results);
        Assert.Equal(DocumentId, result.Id);
        Assert.Equal(ApplicationId, result.ApplicationId);
    }

    [Fact]
    public async Task GetByIdAsync_ReturnsOwnedDocument()
    {
        await using var context = CreateContext();
        AddApplication(context, RentalApplicationStatus.Draft);
        AddDocument(context);
        await context.SaveChangesAsync();
        var service = CreateService(context, new FakeFileStorageService());

        var result = await service.GetByIdAsync(DocumentId, TenantId);

        Assert.NotNull(result);
        Assert.Equal(DocumentId, result.Id);
        Assert.Equal(ApplicationId, result.ApplicationId);
        Assert.Equal("evidence.pdf", result.OriginalFileName);
    }

    [Fact]
    public async Task GetByIdAsync_ForOwnershipMismatch_ReturnsSafeNotFound()
    {
        await using var context = CreateContext();
        AddApplication(context, RentalApplicationStatus.Draft);
        AddDocument(context);
        await context.SaveChangesAsync();
        var service = CreateService(context, new FakeFileStorageService());

        var result = await service.GetByIdAsync(DocumentId, OtherTenantId);

        Assert.Null(result);
    }

    [Fact]
    public async Task GenerateDownloadUrlAsync_RequestsShortLivedUrlWithStoredMetadata()
    {
        await using var context = CreateContext();
        AddApplication(context, RentalApplicationStatus.Draft);
        AddDocument(context);
        await context.SaveChangesAsync();
        var storage = new FakeFileStorageService
        {
            DownloadUrl = "https://downloads.invalid/signed-document"
        };
        var service = CreateService(context, storage);

        var result = await service.GenerateDownloadUrlAsync(DocumentId, TenantId);

        Assert.Equal(storage.DownloadUrl, result);
        var request = Assert.Single(storage.DownloadUrlCalls);
        Assert.Equal("test-storage-key", request.StorageKey);
        Assert.Equal("evidence.pdf", request.OriginalFileName);
        Assert.Equal("application/pdf", request.ContentType);
        Assert.Equal(TimeSpan.FromMinutes(10), request.Lifetime);
    }

    [Fact]
    public async Task DeleteAsync_ForEditableApplication_RemovesMetadataAndStorageObject()
    {
        await using var context = CreateContext();
        AddApplication(context, RentalApplicationStatus.ChangesRequested);
        AddDocument(context);
        await context.SaveChangesAsync();
        var storage = new FakeFileStorageService();
        var service = CreateService(context, storage);

        await service.DeleteAsync(DocumentId, TenantId);

        Assert.Empty(await context.ApplicationDocuments.AsNoTracking().ToListAsync());
        var deletion = Assert.Single(storage.DeleteCalls);
        Assert.Equal("test-storage-key", deletion.StorageKey);
    }

    [Fact]
    public async Task DeleteAsync_RejectsOwnershipMismatch()
    {
        await using var context = CreateContext();
        AddApplication(context, RentalApplicationStatus.Draft);
        AddDocument(context);
        await context.SaveChangesAsync();
        var storage = new FakeFileStorageService();
        var service = CreateService(context, storage);

        var exception = await Assert.ThrowsAsync<ApplicationDocumentServiceException>(() =>
            service.DeleteAsync(DocumentId, OtherTenantId));

        Assert.Equal(ApplicationDocumentServiceError.NotFound, exception.Error);
        Assert.Single(await context.ApplicationDocuments.AsNoTracking().ToListAsync());
        Assert.Empty(storage.DeleteCalls);
    }

    [Fact]
    public async Task DeleteAsync_RejectsNonEditableApplicationState()
    {
        await using var context = CreateContext();
        AddApplication(context, RentalApplicationStatus.Approved);
        AddDocument(context);
        await context.SaveChangesAsync();
        var storage = new FakeFileStorageService();
        var service = CreateService(context, storage);

        var exception = await Assert.ThrowsAsync<ApplicationDocumentServiceException>(() =>
            service.DeleteAsync(DocumentId, TenantId));

        Assert.Equal(ApplicationDocumentServiceError.Conflict, exception.Error);
        Assert.Single(await context.ApplicationDocuments.AsNoTracking().ToListAsync());
        Assert.Empty(storage.DeleteCalls);
    }

    private static ApplicationDocumentService CreateService(
        ApplicationDbContext context,
        IFileStorageService storage) =>
        new(context, storage, NullLogger<ApplicationDocumentService>.Instance);

    private static ApplicationDbContext CreateContext()
    {
        var options = CreateOptions<ApplicationDbContext>();
        return new ApplicationDbContext(options);
    }

    private static FailingSaveApplicationDbContext CreateFailingContext()
    {
        var options = CreateOptions<ApplicationDbContext>();
        return new FailingSaveApplicationDbContext(options);
    }

    private static DbContextOptions<TContext> CreateOptions<TContext>()
        where TContext : DbContext
    {
        return new DbContextOptionsBuilder<TContext>()
            .UseInMemoryDatabase($"ApplicationDocumentServiceTests-{Guid.NewGuid()}")
            .ConfigureWarnings(warnings => warnings.Ignore(InMemoryEventId.TransactionIgnoredWarning))
            .Options;
    }

    private static RentalApplication AddApplication(
        ApplicationDbContext context,
        RentalApplicationStatus status,
        Guid? applicationId = null,
        Guid? tenantId = null)
    {
        var application = new RentalApplication
        {
            Id = applicationId ?? ApplicationId,
            TenantId = tenantId ?? TenantId,
            PropertyId = PropertyId,
            MoveInDate = new DateOnly(2026, 10, 1),
            MonthlyIncome = 7500m,
            Occupation = "Engineer",
            NumberOfOccupants = 2,
            Status = status,
            CreatedAt = CreatedAt
        };

        context.RentalApplications.Add(application);
        return application;
    }

    private static ApplicationDocument AddDocument(
        ApplicationDbContext context,
        Guid? documentId = null,
        Guid? applicationId = null,
        DateTimeOffset? uploadedAt = null)
    {
        var document = new ApplicationDocument
        {
            Id = documentId ?? DocumentId,
            ApplicationId = applicationId ?? ApplicationId,
            DocumentType = ApplicationDocumentType.IncomeProof,
            OriginalFileName = "evidence.pdf",
            StorageKey = "test-storage-key",
            ContentType = "application/pdf",
            FileSizeBytes = 128,
            UploadedAt = uploadedAt ?? UploadedAt
        };

        context.ApplicationDocuments.Add(document);
        return document;
    }

    private static Task<ApplicationDocumentResponseDto> UploadAsync(
        ApplicationDocumentService service,
        string contentType = "application/pdf",
        string originalFileName = "evidence.pdf",
        long fileSizeBytes = 128,
        Guid? tenantId = null)
    {
        return service.UploadAsync(
            ApplicationId,
            tenantId ?? TenantId,
            ApplicationDocumentType.IncomeProof,
            new MemoryStream(new byte[] { 1, 2, 3 }),
            originalFileName,
            contentType,
            fileSizeBytes);
    }

    private sealed class FailingSaveApplicationDbContext(
        DbContextOptions<ApplicationDbContext> options) : ApplicationDbContext(options)
    {
        public bool FailNextSave { get; set; }

        public override Task<int> SaveChangesAsync(CancellationToken cancellationToken = default)
        {
            if (FailNextSave)
            {
                FailNextSave = false;
                throw new DbUpdateException("Simulated database persistence failure.");
            }

            return base.SaveChangesAsync(cancellationToken);
        }
    }

    private sealed class FakeFileStorageService : IFileStorageService
    {
        public List<UploadCall> UploadCalls { get; } = [];

        public List<DeleteCall> DeleteCalls { get; } = [];

        public List<DownloadUrlCall> DownloadUrlCalls { get; } = [];

        public Exception? UploadException { get; init; }

        public string DownloadUrl { get; init; } = "https://downloads.invalid/document";

        public Task UploadAsync(
            Stream content,
            string storageKey,
            string contentType,
            CancellationToken cancellationToken = default)
        {
            UploadCalls.Add(new UploadCall(storageKey, contentType));

            return UploadException is null
                ? Task.CompletedTask
                : Task.FromException(UploadException);
        }

        public Task DeleteAsync(
            string storageKey,
            CancellationToken cancellationToken = default)
        {
            DeleteCalls.Add(new DeleteCall(storageKey));
            return Task.CompletedTask;
        }

        public Task<byte[]> DownloadBytesAsync(
            string storageKey,
            long maximumBytes,
            CancellationToken cancellationToken = default) =>
            Task.FromResult(Array.Empty<byte>());

        public Task<string> GenerateDownloadUrlAsync(
            string storageKey,
            string originalFileName,
            string contentType,
            TimeSpan lifetime)
        {
            DownloadUrlCalls.Add(
                new DownloadUrlCall(storageKey, originalFileName, contentType, lifetime));
            return Task.FromResult(DownloadUrl);
        }
    }

    private sealed record UploadCall(string StorageKey, string ContentType);

    private sealed record DeleteCall(string StorageKey);

    private sealed record DownloadUrlCall(
        string StorageKey,
        string OriginalFileName,
        string ContentType,
        TimeSpan Lifetime);
}
