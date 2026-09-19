using Microsoft.EntityFrameworkCore;
using RentFlow.Api.Data;
using RentFlow.Api.DTOs;
using RentFlow.Api.Models;
using RentFlow.Api.Services.Interfaces;

namespace RentFlow.Api.Services;

public class PropertyImageService : IPropertyImageService
{
    private const long MaximumFileSizeBytes = 5 * 1024 * 1024;

    private static readonly TimeSpan SignedUrlLifetime =
        TimeSpan.FromMinutes(30);

    private static readonly IReadOnlyDictionary<string, string>
        AllowedContentTypes =
            new Dictionary<string, string>(
                StringComparer.OrdinalIgnoreCase)
            {
                ["image/jpeg"] = "jpg",
                ["image/png"] = "png"
            };

    private readonly ApplicationDbContext _dbContext;
    private readonly IFileStorageService _fileStorageService;
    private readonly ILogger<PropertyImageService> _logger;

    public PropertyImageService(
        ApplicationDbContext dbContext,
        IFileStorageService fileStorageService,
        ILogger<PropertyImageService> logger)
    {
        _dbContext = dbContext;
        _fileStorageService = fileStorageService;
        _logger = logger;
    }

    public async Task<PropertyImageResponseDto> UploadAsync(
        Guid propertyId,
        Guid landlordId,
        Stream content,
        string originalFileName,
        string contentType,
        long fileSizeBytes,
        CancellationToken cancellationToken = default)
    {
        ValidateIdentifiers(propertyId, landlordId);
        ValidateUpload(content, contentType, fileSizeBytes);

        var propertyExists = await _dbContext.Properties
            .AsNoTracking()
            .AnyAsync(
                property =>
                    property.Id == propertyId &&
                    property.LandlordId == landlordId,
                cancellationToken);

        if (!propertyExists)
        {
            throw new InvalidOperationException(
                "The property was not found or does not belong to this landlord.");
        }

        var normalizedContentType =
            contentType.Trim().ToLowerInvariant();

        var imageId = Guid.NewGuid();

        var storageKey =
            $"properties/{propertyId:N}/images/{imageId:N}." +
            AllowedContentTypes[normalizedContentType];

        await _fileStorageService.UploadAsync(
            content,
            storageKey,
            normalizedContentType,
            cancellationToken);

        var image = new PropertyImage
        {
            Id = imageId,
            PropertyId = propertyId,
            OriginalFileName = SanitizeFileName(originalFileName),
            StorageKey = storageKey,
            ContentType = normalizedContentType,
            FileSizeBytes = fileSizeBytes,
            UploadedAt = DateTimeOffset.UtcNow
        };

        _dbContext.PropertyImages.Add(image);

        try
        {
            await _dbContext.SaveChangesAsync(cancellationToken);
        }
        catch
        {
            await TryDeleteOrphanedUploadAsync(storageKey);
            throw;
        }

        return MapToResponse(image);
    }

    public async Task<IReadOnlyList<PropertyImageResponseDto>>
        GetByPropertyAsync(
            Guid propertyId,
            CancellationToken cancellationToken = default)
    {
        if (propertyId == Guid.Empty)
        {
            throw new ArgumentException(
                "A property ID is required.",
                nameof(propertyId));
        }

        var images = await _dbContext.PropertyImages
            .AsNoTracking()
            .Where(image => image.PropertyId == propertyId)
            .OrderBy(image => image.UploadedAt)
            .ToListAsync(cancellationToken);

        return images
            .Select(MapToResponse)
            .ToList();
    }

    public async Task<string?> GenerateImageUrlAsync(
        Guid imageId,
        CancellationToken cancellationToken = default)
    {
        if (imageId == Guid.Empty)
        {
            throw new ArgumentException(
                "An image ID is required.",
                nameof(imageId));
        }

        var image = await _dbContext.PropertyImages
            .AsNoTracking()
            .FirstOrDefaultAsync(
                item => item.Id == imageId,
                cancellationToken);

        if (image is null)
        {
            return null;
        }

        return await _fileStorageService.GenerateDownloadUrlAsync(
            image.StorageKey,
            image.OriginalFileName,
            image.ContentType,
            SignedUrlLifetime);
    }

    public async Task<bool> DeleteAsync(
        Guid imageId,
        Guid landlordId,
        CancellationToken cancellationToken = default)
    {
        if (imageId == Guid.Empty || landlordId == Guid.Empty)
        {
            return false;
        }

        var image = await _dbContext.PropertyImages
            .FirstOrDefaultAsync(
                item =>
                    item.Id == imageId &&
                    _dbContext.Properties.Any(property =>
                        property.Id == item.PropertyId &&
                        property.LandlordId == landlordId),
                cancellationToken);

        if (image is null)
        {
            return false;
        }

        await _fileStorageService.DeleteAsync(
            image.StorageKey,
            cancellationToken);

        _dbContext.PropertyImages.Remove(image);

        await _dbContext.SaveChangesAsync(cancellationToken);

        return true;
    }

    // Delete all images belonging to a property.
    public async Task DeleteAllForPropertyAsync(
        Guid propertyId,
        Guid landlordId,
        CancellationToken cancellationToken = default)
    {
        ValidateIdentifiers(propertyId, landlordId);

        var propertyExists = await _dbContext.Properties
            .AsNoTracking()
            .AnyAsync(
                property =>
                    property.Id == propertyId &&
                    property.LandlordId == landlordId,
                cancellationToken);

        if (!propertyExists)
        {
            throw new InvalidOperationException(
                "The property was not found or does not belong to this landlord.");
        }

        var images = await _dbContext.PropertyImages
            .Where(image => image.PropertyId == propertyId)
            .ToListAsync(cancellationToken);

        foreach (var image in images)
        {
            await _fileStorageService.DeleteAsync(
                image.StorageKey,
                cancellationToken);
        }

        if (images.Count > 0)
        {
            _dbContext.PropertyImages.RemoveRange(images);

            await _dbContext.SaveChangesAsync(cancellationToken);
        }
    }

    private static void ValidateIdentifiers(
        Guid propertyId,
        Guid landlordId)
    {
        if (propertyId == Guid.Empty)
        {
            throw new ArgumentException(
                "A property ID is required.",
                nameof(propertyId));
        }

        if (landlordId == Guid.Empty)
        {
            throw new ArgumentException(
                "A landlord ID is required.",
                nameof(landlordId));
        }
    }

    private static void ValidateUpload(
        Stream content,
        string contentType,
        long fileSizeBytes)
    {
        if (content is null || !content.CanRead)
        {
            throw new ArgumentException(
                "A readable image file is required.",
                nameof(content));
        }

        if (fileSizeBytes <= 0)
        {
            throw new ArgumentException(
                "The image cannot be empty.",
                nameof(fileSizeBytes));
        }

        if (fileSizeBytes > MaximumFileSizeBytes)
        {
            throw new ArgumentException(
                "The image cannot exceed 5 MB.",
                nameof(fileSizeBytes));
        }

        if (string.IsNullOrWhiteSpace(contentType) ||
            !AllowedContentTypes.ContainsKey(contentType.Trim()))
        {
            throw new ArgumentException(
                "Only JPEG and PNG images are supported.",
                nameof(contentType));
        }
    }

    private async Task TryDeleteOrphanedUploadAsync(
        string storageKey)
    {
        try
        {
            await _fileStorageService.DeleteAsync(
                storageKey,
                CancellationToken.None);
        }
        catch (Exception exception)
        {
            _logger.LogError(
                exception,
                "Property image metadata persistence failed and R2 " +
                "object {StorageKey} could not be removed.",
                storageKey);
        }
    }

    private static string SanitizeFileName(
        string originalFileName)
    {
        var normalized =
            (originalFileName ?? string.Empty).Replace('\\', '/');

        var fileName =
            normalized[(normalized.LastIndexOf('/') + 1)..];

        fileName = new string(
            fileName
                .Where(character => !char.IsControl(character))
                .ToArray())
            .Trim();

        if (string.IsNullOrWhiteSpace(fileName))
        {
            fileName = "property-image";
        }

        return fileName.Length <= 255
            ? fileName
            : fileName[..255];
    }

    private static PropertyImageResponseDto MapToResponse(
        PropertyImage image)
    {
        return new PropertyImageResponseDto
        {
            Id = image.Id,
            PropertyId = image.PropertyId,
            OriginalFileName = image.OriginalFileName,
            ContentType = image.ContentType,
            FileSizeBytes = image.FileSizeBytes,
            UploadedAt = image.UploadedAt
        };
    }
}