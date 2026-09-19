using RentFlow.Api.DTOs;

namespace RentFlow.Api.Services.Interfaces;

public interface IPropertyImageService
{
    Task<PropertyImageResponseDto> UploadAsync(
        Guid propertyId,
        Guid landlordId,
        Stream content,
        string originalFileName,
        string contentType,
        long fileSizeBytes,
        CancellationToken cancellationToken = default);

    Task<IReadOnlyList<PropertyImageResponseDto>> GetByPropertyAsync(
        Guid propertyId,
        CancellationToken cancellationToken = default);

    Task<string?> GenerateImageUrlAsync(
        Guid imageId,
        CancellationToken cancellationToken = default);

    Task<bool> DeleteAsync(
        Guid imageId,
        Guid landlordId,
        CancellationToken cancellationToken = default);
}