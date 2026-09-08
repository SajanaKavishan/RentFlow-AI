using Amazon.Runtime;
using Amazon.S3;
using Amazon.S3.Model;
using Microsoft.Extensions.Options;
using RentFlow.Api.Configuration;
using RentFlow.Api.Services.Interfaces;

namespace RentFlow.Api.Services;

/// <summary>
/// Stores private application documents in Cloudflare R2 through its S3-compatible API.
/// </summary>
public sealed class CloudflareR2StorageService : IFileStorageService, IDisposable
{
    private static readonly TimeSpan MaximumSignedUrlLifetime = TimeSpan.FromDays(7);

    private readonly CloudflareR2Options options;
    private readonly IAmazonS3 client;

    public CloudflareR2StorageService(IOptions<CloudflareR2Options> options)
    {
        this.options = options.Value;

        var credentials = new BasicAWSCredentials(
            this.options.AccessKeyId,
            this.options.SecretAccessKey);

        client = new AmazonS3Client(credentials, new AmazonS3Config
        {
            ServiceURL = $"https://{this.options.AccountId}.r2.cloudflarestorage.com",
            AuthenticationRegion = "auto",
            ForcePathStyle = true
        });
    }

    public async Task UploadAsync(
        Stream content,
        string storageKey,
        string contentType,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(content);
        ArgumentException.ThrowIfNullOrWhiteSpace(storageKey);
        ArgumentException.ThrowIfNullOrWhiteSpace(contentType);

        if (!content.CanRead)
        {
            throw new ArgumentException("The upload stream must be readable.", nameof(content));
        }

        var request = new PutObjectRequest
        {
            BucketName = options.BucketName,
            Key = storageKey,
            InputStream = content,
            ContentType = contentType,
            DisablePayloadSigning = true,
            DisableDefaultChecksumValidation = true
        };

        await client.PutObjectAsync(request, cancellationToken);
    }

    public async Task DeleteAsync(
        string storageKey,
        CancellationToken cancellationToken = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(storageKey);

        await client.DeleteObjectAsync(
            new DeleteObjectRequest
            {
                BucketName = options.BucketName,
                Key = storageKey
            },
            cancellationToken);
    }

    public async Task<byte[]> DownloadBytesAsync(
        string storageKey,
        long maximumBytes,
        CancellationToken cancellationToken = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(storageKey);
        ArgumentOutOfRangeException.ThrowIfLessThan(maximumBytes, 1);

        using var response = await client.GetObjectAsync(
            new GetObjectRequest
            {
                BucketName = options.BucketName,
                Key = storageKey
            },
            cancellationToken);
        using var content = new MemoryStream();
        var buffer = new byte[81920];
        while (true)
        {
            var read = await response.ResponseStream.ReadAsync(buffer, cancellationToken);
            if (read == 0)
            {
                return content.ToArray();
            }

            if (content.Length + read > maximumBytes)
            {
                throw new InvalidDataException("The private object exceeds the permitted retrieval size.");
            }

            await content.WriteAsync(buffer.AsMemory(0, read), cancellationToken);
        }
    }

    public Task<string> GenerateDownloadUrlAsync(
        string storageKey,
        string originalFileName,
        string contentType,
        TimeSpan lifetime)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(storageKey);
        ArgumentException.ThrowIfNullOrWhiteSpace(originalFileName);
        ArgumentException.ThrowIfNullOrWhiteSpace(contentType);

        if (contentType.Contains('\r') || contentType.Contains('\n'))
        {
            throw new ArgumentException(
                "The content type cannot contain newline characters.",
                nameof(contentType));
        }

        if (lifetime <= TimeSpan.Zero || lifetime > MaximumSignedUrlLifetime)
        {
            throw new ArgumentOutOfRangeException(
                nameof(lifetime),
                "The signed URL lifetime must be greater than zero and no more than seven days.");
        }

        var safeFileName = SanitizeDownloadFileName(originalFileName);
        var request = new GetPreSignedUrlRequest
        {
            BucketName = options.BucketName,
            Key = storageKey,
            Verb = HttpVerb.GET,
            Expires = DateTime.UtcNow.Add(lifetime)
        };

        request.ResponseHeaderOverrides.ContentType = contentType;
        request.ResponseHeaderOverrides.ContentDisposition =
            $"attachment; filename=\"{safeFileName}\"";

        return client.GetPreSignedURLAsync(request);
    }

    private static string SanitizeDownloadFileName(string originalFileName)
    {
        var normalized = originalFileName.Replace('\\', '/');
        var fileName = normalized[(normalized.LastIndexOf('/') + 1)..];
        var sanitized = new string(fileName
            .Select(character => character is >= 'a' and <= 'z'
                or >= 'A' and <= 'Z'
                or >= '0' and <= '9'
                or '.' or '-' or '_' or ' '
                    ? character
                    : '_')
            .ToArray())
            .Trim(' ', '.');

        if (string.IsNullOrWhiteSpace(sanitized))
        {
            sanitized = "document";
        }

        return sanitized.Length <= 255 ? sanitized : sanitized[..255];
    }

    public void Dispose()
    {
        client.Dispose();
    }
}
