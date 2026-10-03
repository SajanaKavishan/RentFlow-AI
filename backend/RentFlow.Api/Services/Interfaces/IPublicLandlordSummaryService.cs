using RentFlow.Api.DTOs;

namespace RentFlow.Api.Services.Interfaces;

public interface IPublicLandlordSummaryService
{
    Task<PublicLandlordSummaryDto?> GetForPropertyAsync(
        Guid propertyId,
        CancellationToken cancellationToken = default);

    Task<PublicLandlordImage?> GetImageForPropertyAsync(
        Guid propertyId,
        CancellationToken cancellationToken = default);

    Task<IReadOnlyList<PropertyResponseDto>?> GetListingsForPropertyAsync(
        Guid propertyId,
        CancellationToken cancellationToken = default);
}

public sealed record PublicLandlordImage(byte[] Content, string ContentType);
