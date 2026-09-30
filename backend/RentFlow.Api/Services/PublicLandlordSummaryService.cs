using Microsoft.EntityFrameworkCore;
using RentFlow.Api.Data;
using RentFlow.Api.DTOs;
using RentFlow.Api.Models;
using RentFlow.Api.Services.Interfaces;

namespace RentFlow.Api.Services;

public sealed class PublicLandlordSummaryService(
    ApplicationDbContext dbContext,
    IFileStorageService fileStorageService) : IPublicLandlordSummaryService
{
    private const long MaximumProfileImageBytes = 5 * 1024 * 1024;
    private static readonly HashSet<string> AllowedImageContentTypes =
        new(StringComparer.OrdinalIgnoreCase)
        {
            "image/jpeg",
            "image/png",
            "image/webp"
        };

    public Task<PublicLandlordSummaryDto?> GetForPropertyAsync(
        Guid propertyId,
        CancellationToken cancellationToken = default)
    {
        return dbContext.Properties
            .AsNoTracking()
            .Where(property =>
                property.Id == propertyId
                && property.Landlord.IsActive
                && property.Landlord.Role == UserRole.Landlord)
            .Select(property => new PublicLandlordSummaryDto
            {
                DisplayName = property.Landlord.FullName,
                MemberSinceYear = property.Landlord.CreatedAt.Year,
                HasProfileImage = property.Landlord.ProfileImage != null
            })
            .SingleOrDefaultAsync(cancellationToken);
    }

    public async Task<PublicLandlordImage?> GetImageForPropertyAsync(
        Guid propertyId,
        CancellationToken cancellationToken = default)
    {
        var metadata = await dbContext.Properties
            .AsNoTracking()
            .Where(property =>
                property.Id == propertyId
                && property.Landlord.IsActive
                && property.Landlord.Role == UserRole.Landlord
                && property.Landlord.ProfileImage != null)
            .Select(property => new
            {
                property.Landlord.ProfileImage!.StorageKey,
                property.Landlord.ProfileImage.ContentType,
                property.Landlord.ProfileImage.FileSizeBytes
            })
            .SingleOrDefaultAsync(cancellationToken);

        if (metadata is null
            || metadata.FileSizeBytes <= 0
            || metadata.FileSizeBytes > MaximumProfileImageBytes
            || !AllowedImageContentTypes.Contains(metadata.ContentType))
        {
            return null;
        }

        var content = await fileStorageService.DownloadBytesAsync(
            metadata.StorageKey,
            MaximumProfileImageBytes,
            cancellationToken);

        if (content.LongLength != metadata.FileSizeBytes)
        {
            return null;
        }

        return new PublicLandlordImage(content, metadata.ContentType);
    }
}
