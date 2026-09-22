using Microsoft.EntityFrameworkCore;
using RentFlow.Api.Data;
using RentFlow.Api.DTOs.Maintenance;
using RentFlow.Api.Models;
using RentFlow.Api.Services.Interfaces;

namespace RentFlow.Api.Services;

/// <summary>Manages private R2-backed attachments for tenant maintenance requests.</summary>
public sealed class MaintenanceAttachmentService(
    ApplicationDbContext dbContext,
    IFileStorageService fileStorageService,
    ILogger<MaintenanceAttachmentService> logger) : IMaintenanceAttachmentService
{
    private const long MaximumFileSizeBytes = 10 * 1024 * 1024;
    private static readonly TimeSpan SignedUrlLifetime = TimeSpan.FromMinutes(10);
    private static readonly IReadOnlyDictionary<string, string> AllowedContentTypes = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
    {
        ["image/jpeg"] = "jpg", ["image/png"] = "png", ["image/webp"] = "webp"
    };

    public async Task<MaintenanceAttachmentResponseDto> UploadAsync(Guid requestId, Guid tenantId, Stream content, string fileName, string contentType, long fileSize, string? attachmentType, CancellationToken cancellationToken = default)
    {
        ValidateRequestAndTenantIds(requestId, tenantId);
        ValidateUpload(content, contentType, fileSize, attachmentType);
        await GetOwnedRequestAsync(requestId, tenantId, cancellationToken);

        var normalizedContentType = contentType.Trim().ToLowerInvariant();
        var attachmentId = Guid.NewGuid();
        var storageKey = $"maintenance-requests/{requestId:N}/{attachmentId:N}.{AllowedContentTypes[normalizedContentType]}";
        await fileStorageService.UploadAsync(content, storageKey, normalizedContentType, cancellationToken);

        var attachment = new MaintenanceAttachment
        {
            Id = attachmentId, MaintenanceRequestId = requestId, StorageKey = storageKey,
            FileName = SanitizeFileName(fileName), ContentType = normalizedContentType,
            FileSize = fileSize, AttachmentType = NormalizeOptionalText(attachmentType),
            UploadedByUserId = tenantId, CreatedAt = DateTimeOffset.UtcNow
        };
        dbContext.MaintenanceAttachments.Add(attachment);
        try { await dbContext.SaveChangesAsync(cancellationToken); }
        catch { await TryDeleteOrphanedUploadAsync(storageKey); throw; }
        return Map(attachment);
    }

    public async Task<IReadOnlyList<MaintenanceAttachmentResponseDto>> GetByRequestAsync(Guid requestId, Guid tenantId, CancellationToken cancellationToken = default)
    {
        ValidateRequestAndTenantIds(requestId, tenantId);
        await GetOwnedRequestAsync(requestId, tenantId, cancellationToken);
        var attachments = await dbContext.MaintenanceAttachments.AsNoTracking().Where(x => x.MaintenanceRequestId == requestId).OrderByDescending(x => x.CreatedAt).ToListAsync(cancellationToken);
        return attachments.Select(Map).ToList();
    }

    public async Task<string> GenerateDownloadUrlAsync(Guid requestId, Guid attachmentId, Guid tenantId, CancellationToken cancellationToken = default)
    {
        var attachment = await GetOwnedAttachmentAsync(requestId, attachmentId, tenantId, false, cancellationToken);
        return await fileStorageService.GenerateDownloadUrlAsync(attachment.StorageKey, attachment.FileName, attachment.ContentType, SignedUrlLifetime);
    }

    public async Task DeleteAsync(Guid requestId, Guid attachmentId, Guid tenantId, CancellationToken cancellationToken = default)
    {
        var attachment = await GetOwnedAttachmentAsync(requestId, attachmentId, tenantId, true, cancellationToken);
        await using var transaction = await dbContext.Database.BeginTransactionAsync(cancellationToken);
        dbContext.MaintenanceAttachments.Remove(attachment);
        await dbContext.SaveChangesAsync(cancellationToken);
        try { await fileStorageService.DeleteAsync(attachment.StorageKey, cancellationToken); }
        catch { await transaction.RollbackAsync(CancellationToken.None); throw; }
        try { await transaction.CommitAsync(CancellationToken.None); }
        catch (Exception exception) { logger.LogCritical(exception, "R2 object {StorageKey} was deleted, but the maintenance attachment transaction could not be committed.", attachment.StorageKey); throw; }
    }

    private async Task<MaintenanceRequest> GetOwnedRequestAsync(Guid requestId, Guid tenantId, CancellationToken cancellationToken) =>
        await dbContext.MaintenanceRequests.AsNoTracking().SingleOrDefaultAsync(x => x.Id == requestId && x.TenantId == tenantId, cancellationToken)
        ?? throw MaintenanceRequestServiceException.NotFound("The maintenance request was not found for this tenant.");

    private async Task<MaintenanceAttachment> GetOwnedAttachmentAsync(Guid requestId, Guid attachmentId, Guid tenantId, bool tracking, CancellationToken cancellationToken)
    {
        ValidateRequestAndTenantIds(requestId, tenantId);
        if (attachmentId == Guid.Empty) throw MaintenanceRequestServiceException.Validation("A maintenance attachment ID is required.");
        IQueryable<MaintenanceAttachment> query = dbContext.MaintenanceAttachments;
        if (!tracking) query = query.AsNoTracking();
        return await query.SingleOrDefaultAsync(x => x.Id == attachmentId && x.MaintenanceRequestId == requestId && dbContext.MaintenanceRequests.Any(r => r.Id == requestId && r.TenantId == tenantId), cancellationToken)
            ?? throw MaintenanceRequestServiceException.NotFound("The maintenance attachment was not found for this request.");
    }

    private async Task TryDeleteOrphanedUploadAsync(string storageKey)
    {
        try { await fileStorageService.DeleteAsync(storageKey, CancellationToken.None); }
        catch (Exception exception) { logger.LogError(exception, "Maintenance attachment persistence failed and R2 object {StorageKey} could not be removed.", storageKey); }
    }

    private static void ValidateRequestAndTenantIds(Guid requestId, Guid tenantId)
    {
        if (requestId == Guid.Empty) throw MaintenanceRequestServiceException.Validation("A maintenance request ID is required.");
        if (tenantId == Guid.Empty) throw MaintenanceRequestServiceException.Validation("A tenant ID is required.");
    }
    private static void ValidateUpload(Stream content, string contentType, long fileSize, string? attachmentType)
    {
        if (content is null || !content.CanRead) throw MaintenanceRequestServiceException.Validation("A readable attachment file is required.");
        if (fileSize <= 0) throw MaintenanceRequestServiceException.Validation("The attachment file cannot be empty.");
        if (fileSize > MaximumFileSizeBytes) throw MaintenanceRequestServiceException.Validation("The attachment file cannot exceed 10 MB.");
        if (string.IsNullOrWhiteSpace(contentType) || !AllowedContentTypes.ContainsKey(contentType.Trim())) throw MaintenanceRequestServiceException.Validation("Only JPEG, PNG, and WEBP attachments are supported.");
        if (attachmentType is { Length: > 100 }) throw MaintenanceRequestServiceException.Validation("Attachment type cannot exceed 100 characters.");
    }
    private static string? NormalizeOptionalText(string? value) => string.IsNullOrWhiteSpace(value) ? null : value.Trim();
    private static string SanitizeFileName(string value)
    {
        var normalized = (value ?? string.Empty).Replace('\\', '/');
        var name = new string(normalized[(normalized.LastIndexOf('/') + 1)..].Where(x => !char.IsControl(x)).ToArray()).Trim();
        name = string.IsNullOrWhiteSpace(name) ? "attachment" : name;
        return name.Length <= 255 ? name : name[..255];
    }
    private static MaintenanceAttachmentResponseDto Map(MaintenanceAttachment x) => new() { Id = x.Id, MaintenanceRequestId = x.MaintenanceRequestId, FileName = x.FileName, ContentType = x.ContentType, FileSize = x.FileSize, AttachmentType = x.AttachmentType, UploadedByUserId = x.UploadedByUserId, CreatedAt = x.CreatedAt };
}
