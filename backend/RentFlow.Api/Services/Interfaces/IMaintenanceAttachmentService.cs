using RentFlow.Api.DTOs.Maintenance;

namespace RentFlow.Api.Services.Interfaces;

public interface IMaintenanceAttachmentService
{
    Task<MaintenanceAttachmentResponseDto> UploadAsync(Guid requestId, Guid tenantId, Stream content, string fileName, string contentType, long fileSize, string? attachmentType, CancellationToken cancellationToken = default);
    Task<MaintenanceAttachmentResponseDto> UploadCompletionAsync(Guid requestId, Guid technicianId, Stream content, string fileName, string contentType, long fileSize, CancellationToken cancellationToken = default);
    Task<IReadOnlyList<MaintenanceAttachmentResponseDto>> GetByRequestAsync(Guid requestId, Guid tenantId, CancellationToken cancellationToken = default);
    Task<string> GenerateDownloadUrlAsync(Guid requestId, Guid attachmentId, Guid tenantId, CancellationToken cancellationToken = default);
    Task DeleteAsync(Guid requestId, Guid attachmentId, Guid tenantId, CancellationToken cancellationToken = default);
}
