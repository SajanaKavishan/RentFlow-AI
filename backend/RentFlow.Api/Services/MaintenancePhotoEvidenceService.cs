using Microsoft.Extensions.Options;
using RentFlow.Api.Configuration;
using RentFlow.Api.DTOs.Maintenance;
using RentFlow.Api.Models;
using RentFlow.Api.Services.Interfaces;
using SixLabors.ImageSharp;
using SixLabors.ImageSharp.Formats;
using SixLabors.ImageSharp.Formats.Jpeg;
using SixLabors.ImageSharp.Memory;
using SixLabors.ImageSharp.PixelFormats;
using SixLabors.ImageSharp.Processing;
using ImageConfigurationType = SixLabors.ImageSharp.Configuration;

namespace RentFlow.Api.Services;

/// <summary>Private, bounded pixel preparation. No storage identifiers leave this service.</summary>
public sealed class MaintenancePhotoEvidenceService(
    IFileStorageService storage, ICurrentUserService currentUser, IPropertyAccessGuard accessGuard,
    IOptions<AgentServiceOptions> agentOptions, ILogger<MaintenancePhotoEvidenceService> logger)
    : IMaintenancePhotoEvidenceService
{
    public const int MaximumPhotos = 5;
    public const int MaximumSourceBytes = 10 * 1024 * 1024;
    public const int MaximumSourceDimension = 8192;
    public const long MaximumSourcePixels = 20_000_000;
    public const int MaximumAnalysisDimension = 1280;
    public const int MaximumAnalysisBytes = 512 * 1024;
    public const int MaximumAggregateBytes = 2 * 1024 * 1024;
    // Limit simultaneous decodes across requests, in addition to per-request sequential processing.
    private static readonly SemaphoreSlim DecodeSlots = new(2);
    private static readonly ImageConfigurationType ImageConfiguration = CreateConfiguration();

    public static bool IsSupported(string contentType) =>
        contentType.Trim().ToLowerInvariant() is "image/jpeg" or "image/png" or "image/webp";

    public static IEnumerable<MaintenanceAttachment> Select(Guid requestId, IEnumerable<MaintenanceAttachment> attachments) =>
        attachments.Where(item => item.MaintenanceRequestId == requestId && IsSupported(item.ContentType))
            .OrderBy(item => item.CreatedAt).ThenBy(item => item.Id).Take(MaximumPhotos);

    public async Task PrepareAsync(MaintenanceRequest request, IReadOnlyCollection<MaintenanceAttachment> attachments,
        MaintenanceCoordinationAgentRequest payload, CancellationToken cancellationToken)
    {
        // Defense in depth: controller resource authorization also runs before invoking this service.
        if (!currentUser.IsAuthenticated || currentUser.UserId is not { } userId
            || (currentUser.Role != UserRole.Admin && (currentUser.Role != UserRole.Landlord
                || !await accessGuard.CanAccessPropertyAsync(userId, request.PropertyId, cancellationToken))))
            throw MaintenanceRequestServiceException.Forbidden("You cannot analyze this maintenance request.");

        var photos = new List<MaintenanceEvidencePhoto>();
        var limitations = new HashSet<string>(StringComparer.Ordinal);
        var aggregateBytes = 0;
        using var preparationBudget = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        preparationBudget.CancelAfter(TimeSpan.FromSeconds(Math.Min(8, agentOptions.Value.TimeoutSeconds / 4.0)));
        var token = preparationBudget.Token;
        foreach (var attachment in Select(request.Id, attachments))
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (token.IsCancellationRequested)
            {
                limitations.Add("PhotoUnavailable");
                continue;
            }
            try
            {
                if (attachment.FileSize is <= 0 or > MaximumSourceBytes)
                {
                    limitations.Add("PhotoUnreadable");
                    continue;
                }
                byte[] source;
                try
                {
                    source = await storage.DownloadBytesAsync(attachment.StorageKey, MaximumSourceBytes, token);
                }
                catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
                {
                    limitations.Add("PhotoUnavailable");
                    continue;
                }
                catch (Exception exception) when (exception is not OperationCanceledException)
                {
                    // Do not log exception messages, object keys, filenames, contacts, or provider responses.
                    logger.LogWarning("Maintenance photo retrieval unavailable ({ErrorType}).", exception.GetType().Name);
                    limitations.Add("PhotoUnavailable");
                    continue;
                }
                await DecodeSlots.WaitAsync(token);
                byte[] normalized;
                try
                {
                    normalized = await NormalizeAsync(source, attachment.ContentType, token);
                }
                finally { DecodeSlots.Release(); }
                if (aggregateBytes + normalized.Length > MaximumAggregateBytes)
                {
                    limitations.Add("PhotoUnavailable");
                    continue;
                }
                aggregateBytes += normalized.Length;
                photos.Add(new MaintenanceEvidencePhoto
                {
                    AttachmentId = attachment.Id, ContentType = "image/jpeg",
                    MediaBase64 = Convert.ToBase64String(normalized)
                });
            }
            catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
            { limitations.Add("PhotoUnavailable"); }
            catch (Exception exception) when (exception is not OperationCanceledException)
            {
                logger.LogWarning("Maintenance photo content unreadable ({ErrorType}).", exception.GetType().Name);
                limitations.Add("PhotoUnreadable");
            }
        }
        cancellationToken.ThrowIfCancellationRequested();
        payload.EvidencePhotos = photos;
        payload.PhotoLimitations = limitations.Order(StringComparer.Ordinal).ToArray();
    }

    public static async Task<byte[]> NormalizeAsync(byte[] source, string contentType, CancellationToken token)
    {
        if (source.Length is <= 0 or > MaximumSourceBytes || !IsSupported(contentType))
            throw new InvalidDataException("Unsupported image content.");
        var options = new DecoderOptions { Configuration = ImageConfiguration, MaxFrames = 1 };
        using var input = new MemoryStream(source, writable: false);
        var info = await Image.IdentifyAsync(options, input, token);
        if (info.Width <= 0 || info.Height <= 0 || info.Width > MaximumSourceDimension || info.Height > MaximumSourceDimension
            || (long)info.Width * info.Height > MaximumSourcePixels
            || info.Metadata.DecodedImageFormat?.DefaultMimeType != contentType.Trim().ToLowerInvariant())
            throw new InvalidDataException("Image content or dimensions are unsupported.");
        input.Position = 0;
        using var image = await Image.LoadAsync<Rgba32>(options, input, token);
        token.ThrowIfCancellationRequested();
        image.Mutate(context => context.AutoOrient());
        if (image.Width > MaximumAnalysisDimension || image.Height > MaximumAnalysisDimension)
            image.Mutate(context => context.Resize(new ResizeOptions
            {
                Size = new Size(MaximumAnalysisDimension, MaximumAnalysisDimension), Mode = ResizeMode.Max,
                Sampler = KnownResamplers.Bicubic
            }));
        // Copy pixels into a fresh image: excludes EXIF, XMP, IPTC, ICC and format metadata.
        using var pixelsOnly = new Image<Rgb24>(ImageConfiguration, image.Width, image.Height);
        pixelsOnly.Mutate(context => context.BackgroundColor(Color.White).DrawImage(image, 1));
        using var output = new MemoryStream();
        await pixelsOnly.SaveAsJpegAsync(output, new JpegEncoder { Quality = 80, SkipMetadata = true }, token);
        if (output.Length > MaximumAnalysisBytes)
        {
            token.ThrowIfCancellationRequested();
            pixelsOnly.Mutate(context => context.Resize(new ResizeOptions
            { Size = new Size(960, 960), Mode = ResizeMode.Max, Sampler = KnownResamplers.Bicubic }));
            output.SetLength(0);
            output.Position = 0;
            await pixelsOnly.SaveAsJpegAsync(output, new JpegEncoder { Quality = 65, SkipMetadata = true }, token);
        }
        if (output.Length > MaximumAnalysisBytes) throw new InvalidDataException("Analysis image exceeds its byte limit.");
        token.ThrowIfCancellationRequested();
        return output.ToArray();
    }

    private static ImageConfigurationType CreateConfiguration()
    {
        var configuration = ImageConfigurationType.Default.Clone();
        configuration.MaxDegreeOfParallelism = 1;
        configuration.MemoryAllocator = MemoryAllocator.Create(new MemoryAllocatorOptions
        { MaximumPoolSizeMegabytes = 32, AllocationLimitMegabytes = 192 });
        return configuration;
    }
}
