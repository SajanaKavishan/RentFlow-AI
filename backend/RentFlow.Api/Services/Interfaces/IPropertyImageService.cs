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
        Guid propertyId,
        Guid imageId,
        Guid landlordId,
        CancellationToken cancellationToken = default);

    Task<PropertyImageResponseDto?> SetPrimaryAsync(
        Guid propertyId,
        Guid imageId,
        Guid landlordId,
        CancellationToken cancellationToken = default);

    Task<IReadOnlyList<PropertyImageResponseDto>?> ReorderAsync(
        Guid propertyId,
        Guid landlordId,
        IReadOnlyList<Guid> imageIds,
        CancellationToken cancellationToken = default);

    Task DeleteAllForPropertyAsync(
        Guid propertyId,
        Guid landlordId,
        CancellationToken cancellationToken = default);
}
