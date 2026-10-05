using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using RentFlow.Api.Configuration;
using RentFlow.Api.DTOs.Maintenance;
using RentFlow.Api.Models;
using RentFlow.Api.Services;
using RentFlow.Api.Services.Interfaces;
using SixLabors.ImageSharp;
using SixLabors.ImageSharp.Formats;
using SixLabors.ImageSharp.Formats.Jpeg;
using SixLabors.ImageSharp.Formats.Png;
using SixLabors.ImageSharp.Formats.Webp;
using SixLabors.ImageSharp.Metadata.Profiles.Exif;
using SixLabors.ImageSharp.PixelFormats;
using Xunit;

namespace RentFlow.Api.Tests.Services;

public sealed class MaintenancePhotoEvidenceServiceTests
{
    internal static byte[] ImageBytes(string mime = "image/png", int width = 64, int height = 48, bool metadata = false)
    {
        using var image = new Image<Rgba32>(width, height, Color.Orange.ToPixel<Rgba32>());
        if (metadata)
        {
            image.Metadata.ExifProfile = new ExifProfile();
            image.Metadata.ExifProfile.SetValue(ExifTag.Orientation, (ushort)6);
            image.Metadata.ExifProfile.SetValue(ExifTag.ImageDescription, "private-device-gps-timestamp");
            image.Metadata.ExifProfile.SetValue(ExifTag.GPSLatitudeRef, "N");
        }
        using var stream = new MemoryStream();
        IImageEncoder encoder = mime switch
        {
            "image/jpeg" => new JpegEncoder(), "image/png" => new PngEncoder(),
            "image/webp" => new WebpEncoder(), _ => throw new ArgumentException("Unsupported test type")
        };
        image.Save(stream, encoder);
        return stream.ToArray();
    }

    [Theory]
    [InlineData("image/jpeg")]
    [InlineData("image/png")]
    [InlineData("image/webp")]
    public async Task ValidImages_AreDecodedAndNormalizedToMetadataFreeJpeg(string mime)
    {
        var normalized = await MaintenancePhotoEvidenceService.NormalizeAsync(ImageBytes(mime), mime, default);
        using var image = Image.Load(normalized);
        Assert.Equal("image/jpeg", image.Metadata.DecodedImageFormat!.DefaultMimeType);
        Assert.Equal(64, image.Width);
        Assert.Equal(48, image.Height);
        Assert.Null(image.Metadata.ExifProfile);
        Assert.True(normalized.Length <= MaintenancePhotoEvidenceService.MaximumAnalysisBytes);
    }

    [Fact]
    public async Task OrientationAppliedBeforeAllMetadataIsStripped()
    {
        var normalized = await MaintenancePhotoEvidenceService.NormalizeAsync(ImageBytes("image/jpeg", metadata: true), "image/jpeg", default);
        using var image = Image.Load(normalized);
        Assert.Equal(48, image.Width);
        Assert.Equal(64, image.Height);
        Assert.Null(image.Metadata.ExifProfile);
        Assert.Null(image.Metadata.XmpProfile);
        Assert.Null(image.Metadata.IptcProfile);
        Assert.Null(image.Metadata.IccProfile);
        Assert.DoesNotContain("private-device-gps-timestamp", Encoding.UTF8.GetString(normalized));
    }

    [Fact]
    public async Task LargeDecodableImage_IsResizedWithinBothAnalysisDimensions()
    {
        var normalized = await MaintenancePhotoEvidenceService.NormalizeAsync(ImageBytes(width: 2000, height: 1000), "image/png", default);
        using var image = Image.Load(normalized);
        Assert.Equal(1280, image.Width);
        Assert.Equal(640, image.Height);
    }

    [Theory]
    [InlineData(8193, 1)]
    [InlineData(5000, 5000)]
    public async Task UnsafeSourceDimensions_AreRejectedBeforeFullDecode(int width, int height)
    {
        var source = ImageBytes();
        System.Buffers.Binary.BinaryPrimitives.WriteInt32BigEndian(source.AsSpan(16, 4), width);
        System.Buffers.Binary.BinaryPrimitives.WriteInt32BigEndian(source.AsSpan(20, 4), height);
        // Keep the PNG IHDR checksum valid so this exercises the dimension guard.
        uint crc = uint.MaxValue;
        for (var index = 12; index < 29; index++)
        {
            crc ^= source[index];
            for (var bit = 0; bit < 8; bit++) crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xedb88320u : crc >> 1;
        }
        System.Buffers.Binary.BinaryPrimitives.WriteUInt32BigEndian(source.AsSpan(29, 4), ~crc);
        await Assert.ThrowsAsync<InvalidDataException>(() => MaintenancePhotoEvidenceService.NormalizeAsync(source, "image/png", default));
    }

    [Fact]
    public async Task EmptyMalformedMimeSpoofedOrOversizedBytes_AreRejected()
    {
        foreach (var source in new[] { Array.Empty<byte>(), Encoding.UTF8.GetBytes("not an image"),
                     new byte[MaintenancePhotoEvidenceService.MaximumSourceBytes + 1] })
            await Assert.ThrowsAnyAsync<Exception>(() => MaintenancePhotoEvidenceService.NormalizeAsync(source, "image/png", default));
        await Assert.ThrowsAsync<InvalidDataException>(() =>
            MaintenancePhotoEvidenceService.NormalizeAsync(ImageBytes(), "image/jpeg", default));
        await Assert.ThrowsAnyAsync<Exception>(() =>
            MaintenancePhotoEvidenceService.NormalizeAsync(ImageBytes()[..40], "image/png", default));
    }

    [Theory]
    [InlineData(UserRole.Landlord, false)]
    [InlineData(UserRole.Tenant, true)]
    [InlineData(UserRole.MaintenanceTechnician, true)]
    public async Task UnauthorizedActor_IsDeniedBeforeStorageOrDecode(UserRole role, bool owns)
    {
        var storage = new FakeStorage();
        var request = Request();
        var attachment = Attachment(request.Id, "image/png", "private-key");
        var payload = MaintenanceCoordinationRequestMapper.Map(request, null, [attachment]);
        var exception = await Assert.ThrowsAsync<MaintenanceRequestServiceException>(() =>
            Service(storage, role, owns).PrepareAsync(request, [attachment], payload, default));
        Assert.Equal(MaintenanceRequestServiceError.Forbidden, exception.Error);
        Assert.Empty(storage.Downloads);
    }

    [Theory]
    [InlineData(UserRole.Landlord, true)]
    [InlineData(UserRole.Admin, false)]
    public async Task AllowedActor_RetrievesOnlyCurrentRequestSupportedPhotosInCreationOrder(UserRole role, bool owns)
    {
        var request = Request();
        var attachments = Enumerable.Range(0, 7).Select(index => Attachment(request.Id, "image/png", $"private-{index}", index)).Reverse().ToList();
        attachments.Add(Attachment(Guid.NewGuid(), "image/png", "outside-request", -2));
        attachments.Add(Attachment(request.Id, "application/pdf", "unsupported", -1));
        var storage = new FakeStorage();
        foreach (var attachment in attachments) storage.Objects[attachment.StorageKey] = ImageBytes();
        var payload = MaintenanceCoordinationRequestMapper.Map(request, null, attachments);
        await Service(storage, role, owns).PrepareAsync(request, attachments, payload, default);
        Assert.Equal(Enumerable.Range(0, 5).Select(index => $"private-{index}"), storage.Downloads);
        Assert.Equal(5, payload.EvidencePhotos.Count);
        Assert.Equal(0, storage.UrlCalls);
        Assert.True(payload.EvidencePhotos.Sum(photo => Convert.FromBase64String(photo.MediaBase64).Length)
                    <= MaintenancePhotoEvidenceService.MaximumAggregateBytes);
        var json = JsonSerializer.Serialize(payload);
        foreach (var forbidden in new[] { "private-", "original-private-file", "StorageKey", "FileName", "TenantId", "PropertyId", "private@email.test", "94771234567", "https://" })
            Assert.DoesNotContain(forbidden, json, StringComparison.OrdinalIgnoreCase);
        Assert.Equal(MaintenanceRequestStatus.Submitted, request.Status);
        Assert.Equal(MaintenanceCategory.Plumbing, request.Category);
        Assert.Equal(MaintenancePriority.Normal, request.Priority);
        Assert.Null(request.TechnicianId);
    }

    [Fact]
    public async Task PartialRetrievalAndDecodeFailures_RetainValidPhotosAndSafeClosedFlags()
    {
        var request = Request();
        var attachments = new[] { Attachment(request.Id, "image/png", "valid"),
            Attachment(request.Id, "image/png", "storage-failure", 1), Attachment(request.Id, "image/png", "malformed", 2) };
        var storage = new FakeStorage();
        storage.Objects["valid"] = ImageBytes();
        storage.Objects["malformed"] = [1, 2, 3];
        var payload = MaintenanceCoordinationRequestMapper.Map(request, null, attachments);
        await Service(storage).PrepareAsync(request, attachments, payload, default);
        Assert.Single(payload.EvidencePhotos);
        Assert.Equal(new[] { "PhotoUnavailable", "PhotoUnreadable" }, payload.PhotoLimitations);
        Assert.Equal(3, payload.Attachments.Count);
        Assert.Equal(MaintenanceRequestStatus.Submitted, request.Status);
    }

    [Fact]
    public async Task AllStorageFailuresAndNoPhotos_AllowTextFallbackWithoutRequestMutation()
    {
        var request = Request();
        var storage = new FakeStorage();
        var attachments = new[] { Attachment(request.Id, "image/png", "unavailable") };
        var payload = MaintenanceCoordinationRequestMapper.Map(request, null, attachments);
        await Service(storage).PrepareAsync(request, attachments, payload, default);
        Assert.Empty(payload.EvidencePhotos);
        Assert.Equal(new[] { "PhotoUnavailable" }, payload.PhotoLimitations);
        payload = MaintenanceCoordinationRequestMapper.Map(request, null, []);
        await Service(storage).PrepareAsync(request, [], payload, default);
        Assert.Empty(payload.PhotoLimitations);
        Assert.Equal(MaintenanceRequestStatus.Submitted, request.Status);
    }

    [Fact]
    public async Task CallerCancellation_PropagatesBeforeStorage()
    {
        var request = Request();
        var attachment = Attachment(request.Id, "image/png", "cancelled");
        var storage = new FakeStorage();
        using var cancellation = new CancellationTokenSource();
        cancellation.Cancel();
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => Service(storage).PrepareAsync(request, [attachment],
            MaintenanceCoordinationRequestMapper.Map(request, null, [attachment]), cancellation.Token));
        Assert.Empty(storage.Downloads);
    }

    [Fact]
    public async Task AggregateByteLimit_SkipsOverflowWhileRetainingEarlierPhotos()
    {
        var pixels = new byte[880 * 880 * 3];
        new Random(17).NextBytes(pixels);
        using var noise = Image.LoadPixelData<Rgb24>(pixels, 880, 880);
        using var buffer = new MemoryStream();
        noise.SaveAsPng(buffer);
        var source = buffer.ToArray();
        var normalized = await MaintenancePhotoEvidenceService.NormalizeAsync(source, "image/png", default);
        Assert.InRange(normalized.Length, MaintenancePhotoEvidenceService.MaximumAggregateBytes / 5 + 1,
            MaintenancePhotoEvidenceService.MaximumAnalysisBytes);
        var request = Request();
        var storage = new FakeStorage();
        var attachments = Enumerable.Range(0, 5).Select(index => Attachment(request.Id, "image/png", $"noise-{index}", index)).ToArray();
        foreach (var attachment in attachments) storage.Objects[attachment.StorageKey] = source;
        var payload = MaintenanceCoordinationRequestMapper.Map(request, null, attachments);
        await Service(storage).PrepareAsync(request, attachments, payload, default);
        Assert.Equal(4, payload.EvidencePhotos.Count);
        Assert.Contains("PhotoUnavailable", payload.PhotoLimitations);
        Assert.True(payload.EvidencePhotos.Sum(item => Convert.FromBase64String(item.MediaBase64).Length)
                    <= MaintenancePhotoEvidenceService.MaximumAggregateBytes);
    }

    [Fact]
    public async Task PerImageAnalysisByteLimit_UsesBoundedLowerResolutionForHighEntropyOutput()
    {
        var pixels = new byte[1280 * 1280 * 3];
        new Random(29).NextBytes(pixels);
        using var noise = Image.LoadPixelData<Rgb24>(pixels, 1280, 1280);
        using var buffer = new MemoryStream();
        noise.SaveAsPng(buffer);
        var normalized = await MaintenancePhotoEvidenceService.NormalizeAsync(buffer.ToArray(), "image/png", default);
        using var result = Image.Load(normalized);
        Assert.True(normalized.Length <= MaintenancePhotoEvidenceService.MaximumAnalysisBytes);
        Assert.True(Math.Max(result.Width, result.Height) <= 960);
    }

    [Fact]
    public async Task PreparationSubBudget_StopsRetrievalAndLeavesTextFallback()
    {
        var request = Request();
        var storage = new FakeStorage { Delay = TimeSpan.FromSeconds(3) };
        var attachments = new[] { Attachment(request.Id, "image/png", "slow"), Attachment(request.Id, "image/png", "not-fetched", 1) };
        var payload = MaintenanceCoordinationRequestMapper.Map(request, null, attachments);
        var timer = System.Diagnostics.Stopwatch.StartNew();
        await Service(storage, timeout: 1).PrepareAsync(request, attachments, payload, default);
        Assert.True(timer.Elapsed < TimeSpan.FromSeconds(2));
        Assert.Single(storage.Downloads);
        Assert.Empty(payload.EvidencePhotos);
        Assert.Contains("PhotoUnavailable", payload.PhotoLimitations);
    }

    private static MaintenancePhotoEvidenceService Service(FakeStorage storage, UserRole role = UserRole.Landlord,
        bool owns = true, int timeout = 30) => new(storage, new Actor(role), new Guard(owns),
        Options.Create(new AgentServiceOptions { TimeoutSeconds = timeout }), NullLogger<MaintenancePhotoEvidenceService>.Instance);
    private static MaintenanceRequest Request() => new() { PropertyId = Guid.NewGuid(), TenantId = Guid.NewGuid(),
        Title = "Tap leak", Description = "Call private@email.test +94771234567 about the tap leak.",
        Category = MaintenanceCategory.Plumbing, Priority = MaintenancePriority.Normal, Status = MaintenanceRequestStatus.Submitted };
    private static MaintenanceAttachment Attachment(Guid requestId, string type, string key, int order = 0) => new()
    {
        MaintenanceRequestId = requestId, ContentType = type, StorageKey = key, FileSize = 100,
        FileName = "original-private-file", CreatedAt = DateTimeOffset.UnixEpoch.AddSeconds(order)
    };

    private sealed class Actor(UserRole role) : ICurrentUserService
    {
        public bool IsAuthenticated => true;
        public Guid? UserId => Guid.Parse("10000000-0000-0000-0000-000000000001");
        public UserRole? Role => role;
    }
    private sealed class Guard(bool owns) : IPropertyAccessGuard
    {
        public Task<bool> CanAccessPropertyAsync(Guid a, Guid b, CancellationToken t = default) => Task.FromResult(owns);
        public Task<bool> CanAccessViewingAsync(Guid a, Guid b, CancellationToken t = default) => throw new NotSupportedException();
        public Task<bool> CanAccessApplicationAsync(Guid a, Guid b, CancellationToken t = default) => throw new NotSupportedException();
        public Task<bool> CanAccessRentalOfferAsync(Guid a, Guid b, CancellationToken t = default) => throw new NotSupportedException();
        public Task<bool> CanAccessDocumentAsync(Guid a, Guid b, CancellationToken t = default) => throw new NotSupportedException();
        public Task<bool> CanAccessWorkflowAsync(Guid a, Guid b, CancellationToken t = default) => throw new NotSupportedException();
        public Task<bool> CanAccessPricingAnalysisWorkflowAsync(Guid a, Guid b, CancellationToken t = default) => throw new NotSupportedException();
    }
    private sealed class FakeStorage : IFileStorageService
    {
        public Dictionary<string, byte[]> Objects { get; } = [];
        public List<string> Downloads { get; } = [];
        public int UrlCalls { get; private set; }
        public TimeSpan Delay { get; init; }
        public async Task<byte[]> DownloadBytesAsync(string key, long maximum, CancellationToken token = default)
        {
            Downloads.Add(key);
            Assert.Equal(MaintenancePhotoEvidenceService.MaximumSourceBytes, maximum);
            if (Delay > TimeSpan.Zero) await Task.Delay(Delay, token);
            return Objects.TryGetValue(key, out var bytes) ? bytes : throw new IOException("private-storage-secret");
        }
        public Task UploadAsync(Stream a, string b, string c, CancellationToken t = default) => throw new NotSupportedException();
        public Task DeleteAsync(string a, CancellationToken t = default) => throw new NotSupportedException();
        public Task<string> GenerateDownloadUrlAsync(string a, string b, string c, TimeSpan d) { UrlCalls++; throw new NotSupportedException(); }
        public Task<string> GenerateInlineUrlAsync(string a, string b, TimeSpan c) { UrlCalls++; throw new NotSupportedException(); }
    }
}
