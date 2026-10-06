using Microsoft.EntityFrameworkCore;
using RentFlow.Api.Data;
using RentFlow.Api.DTOs.Maintenance;
using RentFlow.Api.Models;
using RentFlow.Api.Services.Interfaces;
using Microsoft.Extensions.Options;
using RentFlow.Api.Configuration;

namespace RentFlow.Api.Services;

public sealed class MaintenanceCoordinationService(
    ApplicationDbContext dbContext,
    IMaintenanceCoordinationAgentClient agentClient,
    IMaintenancePhotoEvidenceService? photoEvidenceService = null,
    IOptions<AgentServiceOptions>? agentOptions = null) : IMaintenanceCoordinationService
{
    public async Task<MaintenanceCoordinationResult> AnalyzeAsync(Guid requestId, CancellationToken cancellationToken = default)
    {
        var started = System.Diagnostics.Stopwatch.StartNew();
        var seconds = agentOptions?.Value.TimeoutSeconds ?? 30;
        using var budget = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        budget.CancelAfter(TimeSpan.FromSeconds(seconds));
        cancellationToken = budget.Token;
        if (requestId == Guid.Empty)
        {
            throw MaintenanceRequestServiceException.Validation("A maintenance request ID is required.");
        }

        var request = await dbContext.MaintenanceRequests.AsNoTracking().SingleOrDefaultAsync(x => x.Id == requestId, cancellationToken)
            ?? throw MaintenanceRequestServiceException.NotFound($"Maintenance request '{requestId}' was not found.");
        var estimate = await dbContext.RepairEstimates.AsNoTracking().Where(x => x.MaintenanceRequestId == requestId).OrderByDescending(x => x.VersionNumber).ThenByDescending(x => x.CreatedAt).FirstOrDefaultAsync(cancellationToken);
        var attachments = await dbContext.MaintenanceAttachments.AsNoTracking().Where(x => x.MaintenanceRequestId == requestId).ToListAsync(cancellationToken);

        var payload = MaintenanceCoordinationRequestMapper.Map(request, estimate, attachments);
        if (photoEvidenceService is not null)
            await photoEvidenceService.PrepareAsync(request, attachments, payload, cancellationToken);
        payload.RemainingBudgetSeconds = Math.Max(0.1, seconds - started.Elapsed.TotalSeconds - 0.5);
        var response = await agentClient.AnalyzeAsync(payload, cancellationToken);
        var current = await dbContext.MaintenanceRequests.AsNoTracking().SingleAsync(x => x.Id == requestId, cancellationToken);
        if (current.Status.ToString() != payload.CurrentStatus)
            throw new MaintenanceCoordinationAgentClientException(MaintenanceCoordinationAgentClientError.MalformedResponse, "The request changed during analysis. Run a new analysis.");
        MaintenanceCoordinationResultValidator.Validate(payload, response);
        return response.Result;
    }
}
