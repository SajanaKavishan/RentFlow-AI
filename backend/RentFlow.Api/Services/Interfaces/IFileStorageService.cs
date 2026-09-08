namespace RentFlow.Api.Services.Interfaces;

/// <summary>
/// Defines the storage operations required by application document services.
/// </summary>
public interface IFileStorageService
{
    Task UploadAsync(
        Stream content,
        string storageKey,
        string contentType,
        CancellationToken cancellationToken = default);

    Task DeleteAsync(
        string storageKey,
        CancellationToken cancellationToken = default);

    /// <summary>
    /// Retrieves a private object for trusted server-side processing only.
    /// </summary>
    Task<byte[]> DownloadBytesAsync(
        string storageKey,
        long maximumBytes,
        CancellationToken cancellationToken = default);

    Task<string> GenerateDownloadUrlAsync(
        string storageKey,
        string originalFileName,
        string contentType,
        TimeSpan lifetime);
}
