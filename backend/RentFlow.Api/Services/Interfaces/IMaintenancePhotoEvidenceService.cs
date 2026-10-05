using RentFlow.Api.DTOs.Maintenance;
using RentFlow.Api.Models;

namespace RentFlow.Api.Services.Interfaces;

public interface IMaintenancePhotoEvidenceService
{
    Task PrepareAsync(MaintenanceRequest request, IReadOnlyCollection<MaintenanceAttachment> attachments,
        MaintenanceCoordinationAgentRequest payload, CancellationToken cancellationToken);
}
