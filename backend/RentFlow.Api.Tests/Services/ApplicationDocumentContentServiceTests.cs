using System.Text.Json;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using RentFlow.Api.Configuration;
using RentFlow.Api.Models;
using RentFlow.Api.Services;
using RentFlow.Api.Services.Interfaces;
using Xunit;

namespace RentFlow.Api.Tests.Services;

public sealed class ApplicationDocumentContentServiceTests
{
    private static readonly Guid ApplicationId = Guid.NewGuid();

    [Theory]
    [InlineData("application/pdf")]
    [InlineData("image/jpeg")]
    [InlineData("image/png")]
    public async Task PrepareForAnalysisAsync_AuthorizedSupportedDocumentReturnsSafeContent(
        string contentType)
    {
        byte[] bytes = [1, 2, 3, 4];
        var storage = new FakeStorage { Content = bytes };
        var document = CreateDocument(contentType, bytes.Length);

        var result = await CreateService(storage).PrepareForAnalysisAsync(ApplicationId, document);

        Assert.NotNull(result.Input);
        Assert.Equal(Convert.ToBase64String(bytes), result.Input.ContentBase64);
        Assert.Equal(document.Id, result.Input.DocumentId);
        Assert.Equal(document.DocumentType, result.Input.DocumentType);
        Assert.Single(storage.DownloadedKeys);

        var json = JsonSerializer.Serialize(result.Input, new JsonSerializerOptions(JsonSerializerDefaults.Web));
        Assert.DoesNotContain("storageKey", json, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("signedUrl", json, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("publicUrl", json, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain(document.StorageKey, json, StringComparison.Ordinal);
        Assert.Contains("\"documentType\":\"IncomeProof\"", json, StringComparison.Ordinal);
    }

    [Fact]
    public async Task PrepareForAnalysisAsync_UnsupportedMimeIsExcludedSafely()
    {
        var storage = new FakeStorage { Content = [1] };
        var document = CreateDocument("text/plain", 1);

        var result = await CreateService(storage).PrepareForAnalysisAsync(ApplicationId, document);

        Assert.Null(result.Input);
        Assert.Equal("unsupported_content_type", result.WarningCode);
        Assert.Empty(storage.DownloadedKeys);
    }

    [Fact]
    public async Task PrepareForAnalysisAsync_OversizedMetadataIsExcludedSafely()
    {
        var storage = new FakeStorage { Content = [1] };
        var document = CreateDocument("application/pdf", DocumentAnalysisOptions.UploadLimitBytes + 1);

        var result = await CreateService(storage).PrepareForAnalysisAsync(ApplicationId, document);

        Assert.Null(result.Input);
        Assert.Equal("invalid_file_size", result.WarningCode);
        Assert.Empty(storage.DownloadedKeys);
    }

    [Fact]
    public async Task PrepareForAnalysisAsync_RetrievalFailureReturnsSanitizedWarning()
    {
        var storage = new FakeStorage
        {
            DownloadException = new InvalidOperationException("secret storage provider detail")
        };
        var document = CreateDocument("application/pdf", 1);

        var result = await CreateService(storage).PrepareForAnalysisAsync(ApplicationId, document);

        Assert.Null(result.Input);
        Assert.Equal("retrieval_failed", result.WarningCode);
        Assert.DoesNotContain("secret", result.Warning!, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("provider", result.Warning!, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task PrepareForAnalysisAsync_DocumentFromAnotherApplicationIsExcluded()
    {
        var storage = new FakeStorage { Content = [1] };
        var document = CreateDocument("application/pdf", 1);

        var result = await CreateService(storage).PrepareForAnalysisAsync(Guid.NewGuid(), document);

        Assert.Null(result.Input);
        Assert.Equal("application_mismatch", result.WarningCode);
        Assert.Empty(storage.DownloadedKeys);
    }

    [Fact]
    public async Task PrepareForAnalysisAsync_RetrievedSizeMismatchIsExcluded()
    {
        var storage = new FakeStorage { Content = [1, 2] };
        var document = CreateDocument("application/pdf", 1);

        var result = await CreateService(storage).PrepareForAnalysisAsync(ApplicationId, document);

        Assert.Null(result.Input);
        Assert.Equal("content_validation_failed", result.WarningCode);
    }

    private static ApplicationDocumentContentService CreateService(FakeStorage storage) =>
        new(
            storage,
            Options.Create(new DocumentAnalysisOptions()),
            NullLogger<ApplicationDocumentContentService>.Instance);

    private static ApplicationDocument CreateDocument(string contentType, long sizeBytes) => new()
    {
        ApplicationId = ApplicationId,
        DocumentType = ApplicationDocumentType.IncomeProof,
        OriginalFileName = "income-proof.pdf",
        StorageKey = "private/application/storage-key",
        ContentType = contentType,
        FileSizeBytes = sizeBytes
    };

    private sealed class FakeStorage : IFileStorageService
    {
        public byte[] Content { get; init; } = [];
        public Exception? DownloadException { get; init; }
        public List<string> DownloadedKeys { get; } = [];

        public Task UploadAsync(Stream content, string storageKey, string contentType,
            CancellationToken cancellationToken = default) => Task.CompletedTask;

        public Task DeleteAsync(string storageKey,
            CancellationToken cancellationToken = default) => Task.CompletedTask;

        public Task<byte[]> DownloadBytesAsync(string storageKey,
            long maximumBytes,
            CancellationToken cancellationToken = default)
        {
            DownloadedKeys.Add(storageKey);
            return DownloadException is null
                ? Task.FromResult(Content)
                : Task.FromException<byte[]>(DownloadException);
        }

        public Task<string> GenerateDownloadUrlAsync(string storageKey, string originalFileName,
            string contentType, TimeSpan lifetime) => Task.FromResult("https://unused.invalid");
    }
}
