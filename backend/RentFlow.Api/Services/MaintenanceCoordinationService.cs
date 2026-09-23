using Microsoft.EntityFrameworkCore;
using RentFlow.Api.Data;
using RentFlow.Api.DTOs.Maintenance;
using RentFlow.Api.Models;
using RentFlow.Api.Services.Interfaces;

namespace RentFlow.Api.Services;

public sealed class MaintenanceCoordinationService(
    ApplicationDbContext dbContext,
    IMaintenanceCoordinationAgentClient agentClient) : IMaintenanceCoordinationService
{
    public async Task<MaintenanceCoordinationResult> AnalyzeAsync(Guid requestId, CancellationToken cancellationToken = default)
    {
        if (requestId == Guid.Empty)
        {
            throw MaintenanceRequestServiceException.Validation("A maintenance request ID is required.");
        }

        var request = await dbContext.MaintenanceRequests.AsNoTracking().SingleOrDefaultAsync(x => x.Id == requestId, cancellationToken)
            ?? throw MaintenanceRequestServiceException.NotFound($"Maintenance request '{requestId}' was not found.");
        var estimate = await dbContext.RepairEstimates.AsNoTracking().Where(x => x.MaintenanceRequestId == requestId).OrderByDescending(x => x.VersionNumber).ThenByDescending(x => x.CreatedAt).FirstOrDefaultAsync(cancellationToken);
        var attachments = await dbContext.MaintenanceAttachments.AsNoTracking().Where(x => x.MaintenanceRequestId == requestId).ToListAsync(cancellationToken);

        var response = await agentClient.AnalyzeAsync(new MaintenanceCoordinationAgentRequest
        {
            MaintenanceRequestId = request.Id,
            Title = request.Title,
            Description = request.Description,
            Category = request.Category.ToString().ToLowerInvariant(),
            Priority = ToAgentPriority(request.Priority),
            CurrentStatus = ToAgentStatus(request.Status),
            AssignedTechnicianId = request.TechnicianId,
            RepairEstimate = estimate is null ? null : new MaintenanceCoordinationEstimate
            {
                Amount = estimate.TotalCost,
                Notes = estimate.Notes
            },
            Attachments = attachments.Select(x => new MaintenanceCoordinationAttachment
            {
                AttachmentId = x.Id,
                FileName = x.FileName,
                ContentType = x.ContentType
            }).ToArray()
        }, cancellationToken);

        return response.Result;
    }

    private static string ToAgentPriority(MaintenancePriority priority) => priority switch
    {
        MaintenancePriority.Low => "low",
        MaintenancePriority.Normal => "medium",
        MaintenancePriority.High => "high",
        MaintenancePriority.Emergency => "urgent",
        _ => "medium"
    };

    private static string ToAgentStatus(MaintenanceRequestStatus status) => status switch
    {
        MaintenanceRequestStatus.InProgress => "in_progress",
        MaintenanceRequestStatus.Completed => "completed",
        MaintenanceRequestStatus.Cancelled => "cancelled",
        _ => status is MaintenanceRequestStatus.Submitted or MaintenanceRequestStatus.Triaged or MaintenanceRequestStatus.Assigned or MaintenanceRequestStatus.EstimatePending or MaintenanceRequestStatus.EstimateSubmitted or MaintenanceRequestStatus.AwaitingLandlordApproval ? "open" : "on_hold"
    };
}