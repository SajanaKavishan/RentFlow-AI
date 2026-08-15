namespace RentFlow.Api.Services.Interfaces;

/// <summary>
/// Defines the storage operations required by application document services.
/// </summary>
public interface IFileStorageService
{
    Task<string> SaveAsync(
        Stream content,
        string originalFileName,
        string contentType,
        CancellationToken cancellationToken = default);

    Task DeleteAsync(
        string fileUrl,
        CancellationToken cancellationToken = default);
}
