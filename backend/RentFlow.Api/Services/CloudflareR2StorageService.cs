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

    public Task<string> GenerateSignedGetUrlAsync(
        string storageKey,
        TimeSpan lifetime)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(storageKey);

        if (lifetime <= TimeSpan.Zero || lifetime > MaximumSignedUrlLifetime)
        {
            throw new ArgumentOutOfRangeException(
                nameof(lifetime),
                "The signed URL lifetime must be greater than zero and no more than seven days.");
        }

        return client.GetPreSignedURLAsync(new GetPreSignedUrlRequest
        {
            BucketName = options.BucketName,
            Key = storageKey,
            Verb = HttpVerb.GET,
            Expires = DateTime.UtcNow.Add(lifetime)
        });
    }

    public void Dispose()
    {
        client.Dispose();
    }
}
