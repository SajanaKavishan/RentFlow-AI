using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using RentFlow.Api.DTOs.Maintenance;
using RentFlow.Api.Models;
using RentFlow.Api.Services;
using RentFlow.Api.Services.Interfaces;

namespace RentFlow.Api.Controllers;

/// <summary>
/// Handles HTTP requests for maintenance requests.
/// </summary>
[ApiController]
[Authorize]
[Route("api/maintenance-requests")]
public class MaintenanceRequestsController(
    IMaintenanceRequestService maintenanceRequestService,
    IMaintenanceAttachmentService maintenanceAttachmentService,
    IMaintenanceCoordinationService maintenanceCoordinationService,
    IMaintenanceCoordinationOrchestrator maintenanceCoordinationOrchestrator,
    ICurrentUserService currentUserService,
    ILogger<MaintenanceRequestsController> logger) : ControllerBase
{
    [HttpPost]
    [ProducesResponseType<MaintenanceRequestResponseDto>(StatusCodes.Status201Created)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    public async Task<ActionResult<MaintenanceRequestResponseDto>> Create(
        [FromQuery] Guid? tenantId,
        [FromBody] CreateMaintenanceRequestDto request,
        CancellationToken cancellationToken)
    {
        if (!TryGetAuthorizedUserId([UserRole.Tenant], out var currentUserId, out var authResult))
        {
            return authResult;
        }

        if (!RouteActorMatchesCurrentUser(tenantId, currentUserId))
        {
            return Forbid();
        }

        return await ExecuteAsync(
            () => maintenanceRequestService.CreateAsync(currentUserId, request, cancellationToken),
            result => CreatedAtAction(nameof(GetById), new { id = result.Id }, result));
    }

    [HttpGet("{id:guid}")]
    [ProducesResponseType<MaintenanceRequestResponseDto>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    public async Task<ActionResult<MaintenanceRequestResponseDto>> GetById(
        Guid id,
        CancellationToken cancellationToken)
    {
        if (!TryGetAuthorizedUserId(
                [UserRole.Tenant, UserRole.MaintenanceTechnician, UserRole.Landlord, UserRole.Admin],
                out var currentUserId,
                out var authResult))
        {
            return authResult;
        }

        return await ExecuteAsync(
            () => GetAuthorizedRequestAsync(id, currentUserId, cancellationToken),
            result => Ok(result));
    }

    [HttpPost("{id:guid}/coordination-analysis")]
    [ProducesResponseType<MaintenanceCoordinationResult>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status502BadGateway)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    public async Task<ActionResult<MaintenanceCoordinationResult>> CoordinationAnalysis(
        Guid id,
        CancellationToken cancellationToken)
    {
        if (!TryGetAuthorizedUserId([UserRole.Landlord, UserRole.Admin], out var currentUserId, out var authResult))
        {
            return authResult;
        }

        return await ExecuteAsync(
            async () =>
            {
                await GetAuthorizedRequestAsync(id, currentUserId, cancellationToken);
                return await maintenanceCoordinationService.AnalyzeAsync(id, cancellationToken);
            },
            result => Ok(result));
    }

    [HttpPost("{id:guid}/coordination-workflows")]
    [ProducesResponseType<MaintenanceCoordinationWorkflow>(StatusCodes.Status201Created)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status409Conflict)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    public async Task<ActionResult<MaintenanceCoordinationWorkflow>> StartCoordinationWorkflow(
        Guid id,
        CancellationToken cancellationToken)
    {
        if (!TryGetAuthorizedUserId([UserRole.Landlord, UserRole.Admin], out var currentUserId, out var authResult))
        {
            return authResult;
        }

        return await ExecuteAsync(
            async () =>
            {
                await GetAuthorizedRequestAsync(id, currentUserId, cancellationToken);
                return await maintenanceCoordinationOrchestrator.StartAnalysisAsync(id, cancellationToken);
            },
            result => CreatedAtAction(nameof(GetCoordinationWorkflow), new { id, workflowId = result.Id }, result));
    }

    [HttpGet("{id:guid}/coordination-workflows/{workflowId:guid}")]
    [ProducesResponseType<MaintenanceCoordinationWorkflow>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    public async Task<ActionResult<MaintenanceCoordinationWorkflow>> GetCoordinationWorkflow(
        Guid id,
        Guid workflowId,
        CancellationToken cancellationToken)
    {
        if (!TryGetAuthorizedUserId([UserRole.Landlord, UserRole.Admin], out var currentUserId, out var authResult))
        {
            return authResult;
        }

        return await ExecuteAsync(
            async () =>
            {
                await GetAuthorizedRequestAsync(id, currentUserId, cancellationToken);
                var workflow = await maintenanceCoordinationOrchestrator.GetByIdAsync(workflowId, cancellationToken)
                    ?? throw MaintenanceRequestServiceException.NotFound($"Maintenance coordination workflow '{workflowId}' was not found.");

                if (workflow.MaintenanceRequestId != id)
                {
                    throw MaintenanceRequestServiceException.NotFound($"Maintenance coordination workflow '{workflowId}' was not found.");
                }

                return workflow;
            },
            result => Ok(result));
    }

    [HttpPatch("{id:guid}/coordination-workflows/{workflowId:guid}/approve")]
    [ProducesResponseType<MaintenanceCoordinationWorkflow>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status409Conflict)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    public async Task<ActionResult<MaintenanceCoordinationWorkflow>> ApproveCoordinationWorkflow(
        Guid id,
        Guid workflowId,
        [FromBody] MaintenanceCoordinationDecisionDto request,
        CancellationToken cancellationToken)
    {
        if (!TryGetAuthorizedUserId([UserRole.Landlord, UserRole.Admin], out var currentUserId, out var authResult))
        {
            return authResult;
        }

        return await ExecuteAsync(
            async () =>
            {
                await GetAuthorizedRequestAsync(id, currentUserId, cancellationToken);
                var workflow = await maintenanceCoordinationOrchestrator.GetByIdAsync(workflowId, cancellationToken)
                    ?? throw MaintenanceRequestServiceException.NotFound($"Maintenance coordination workflow '{workflowId}' was not found.");

                if (workflow.MaintenanceRequestId != id)
                {
                    throw MaintenanceRequestServiceException.NotFound($"Maintenance coordination workflow '{workflowId}' was not found.");
                }

                return await maintenanceCoordinationOrchestrator.ApproveAsync(workflowId, currentUserId, request.DecisionNotes, cancellationToken);
            },
            result => Ok(result));
    }

    [HttpPatch("{id:guid}/coordination-workflows/{workflowId:guid}/reject")]
    [ProducesResponseType<MaintenanceCoordinationWorkflow>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status409Conflict)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    public async Task<ActionResult<MaintenanceCoordinationWorkflow>> RejectCoordinationWorkflow(
        Guid id,
        Guid workflowId,
        [FromBody] MaintenanceCoordinationDecisionDto request,
        CancellationToken cancellationToken)
    {
        if (!TryGetAuthorizedUserId([UserRole.Landlord, UserRole.Admin], out var currentUserId, out var authResult))
        {
            return authResult;
        }

        return await ExecuteAsync(
            async () =>
            {
                await GetAuthorizedRequestAsync(id, currentUserId, cancellationToken);
                var workflow = await maintenanceCoordinationOrchestrator.GetByIdAsync(workflowId, cancellationToken)
                    ?? throw MaintenanceRequestServiceException.NotFound($"Maintenance coordination workflow '{workflowId}' was not found.");

                if (workflow.MaintenanceRequestId != id)
                {
                    throw MaintenanceRequestServiceException.NotFound($"Maintenance coordination workflow '{workflowId}' was not found.");
                }

                return await maintenanceCoordinationOrchestrator.RejectAsync(workflowId, currentUserId, request.DecisionNotes, cancellationToken);
            },
            result => Ok(result));
    }

    [HttpGet("tenant/{tenantId:guid}")]
    [ProducesResponseType<IReadOnlyList<MaintenanceRequestSummaryDto>>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    public async Task<ActionResult<IReadOnlyList<MaintenanceRequestSummaryDto>>> GetByTenant(
        Guid tenantId,
        CancellationToken cancellationToken)
    {
        if (!TryGetAuthorizedUserId([UserRole.Tenant], out var currentUserId, out var authResult))
        {
            return authResult;
        }

        if (tenantId != currentUserId)
        {
            return Forbid();
        }

        return await ExecuteAsync(
            () => maintenanceRequestService.GetByTenantAsync(currentUserId, cancellationToken),
            result => Ok(result));
    }

    [HttpGet("property/{propertyId:guid}")]
    [ProducesResponseType<IReadOnlyList<MaintenanceRequestSummaryDto>>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    public async Task<ActionResult<IReadOnlyList<MaintenanceRequestSummaryDto>>> GetByProperty(
        Guid propertyId,
        CancellationToken cancellationToken)
    {
        if (!TryGetAuthorizedUserId([UserRole.Landlord, UserRole.Admin], out _, out var authResult))
        {
            return authResult;
        }

        return await ExecuteAsync(
            () => maintenanceRequestService.GetByPropertyAsync(propertyId, cancellationToken),
            result => Ok(result));
    }

    [HttpGet("{id:guid}/history")]
    [ProducesResponseType<IReadOnlyList<MaintenanceStatusHistoryResponseDto>>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    public async Task<ActionResult<IReadOnlyList<MaintenanceStatusHistoryResponseDto>>> GetHistory(
        Guid id,
        CancellationToken cancellationToken)
    {
        if (!TryGetAuthorizedUserId(
                [UserRole.Tenant, UserRole.MaintenanceTechnician, UserRole.Landlord, UserRole.Admin],
                out var currentUserId,
                out var authResult))
        {
            return authResult;
        }

        return await ExecuteAsync(
            async () =>
            {
                await GetAuthorizedRequestAsync(id, currentUserId, cancellationToken);
                return await maintenanceRequestService.GetHistoryAsync(id, cancellationToken);
            },
            result => Ok(result));
    }

    [HttpPut("{id:guid}")]
    [ProducesResponseType<MaintenanceRequestResponseDto>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status409Conflict)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    public async Task<ActionResult<MaintenanceRequestResponseDto>> Update(
        Guid id,
        [FromQuery] Guid? tenantId,
        [FromBody] UpdateMaintenanceRequestDto request,
        CancellationToken cancellationToken)
    {
        if (!TryGetAuthorizedUserId([UserRole.Tenant], out var currentUserId, out var authResult))
        {
            return authResult;
        }

        if (!RouteActorMatchesCurrentUser(tenantId, currentUserId))
        {
            return Forbid();
        }

        return await ExecuteAsync(
            () => maintenanceRequestService.UpdateTenantRequestAsync(
                id,
                currentUserId,
                request,
                cancellationToken),
            result => Ok(result));
    }

    [HttpPatch("{id:guid}/triage")]
    [ProducesResponseType<MaintenanceRequestResponseDto>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status409Conflict)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    public async Task<ActionResult<MaintenanceRequestResponseDto>> Triage(
        Guid id,
        [FromBody] TriageMaintenanceRequestDto request,
        CancellationToken cancellationToken)
    {
        if (!TryGetAuthorizedUserId([UserRole.Landlord, UserRole.Admin], out _, out var authResult))
        {
            return authResult;
        }

        return await ExecuteAsync(
            () => maintenanceRequestService.TriageAsync(id, request, cancellationToken),
            result => Ok(result));
    }

    [HttpPatch("{id:guid}/assign-technician")]
    [ProducesResponseType<MaintenanceRequestResponseDto>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status409Conflict)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    public async Task<ActionResult<MaintenanceRequestResponseDto>> AssignTechnician(
        Guid id,
        [FromBody] AssignTechnicianDto request,
        CancellationToken cancellationToken)
    {
        if (!TryGetAuthorizedUserId([UserRole.Landlord, UserRole.Admin], out _, out var authResult))
        {
            return authResult;
        }

        return await ExecuteAsync(
            () => maintenanceRequestService.AssignTechnicianAsync(id, request, cancellationToken),
            result => Ok(result));
    }

    [HttpPatch("{id:guid}/estimate-pending")]
    [ProducesResponseType<MaintenanceRequestResponseDto>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status409Conflict)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    public async Task<ActionResult<MaintenanceRequestResponseDto>> MarkEstimatePending(
        Guid id,
        CancellationToken cancellationToken)
    {
        if (!TryGetAuthorizedUserId([UserRole.Landlord, UserRole.Admin], out _, out var authResult))
        {
            return authResult;
        }

        return await ExecuteAsync(
            () => maintenanceRequestService.MarkEstimatePendingAsync(id, cancellationToken),
            result => Ok(result));
    }

    [HttpPost("{id:guid}/estimates")]
    [ProducesResponseType<RepairEstimateResponseDto>(StatusCodes.Status201Created)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status409Conflict)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    public async Task<ActionResult<RepairEstimateResponseDto>> SubmitEstimate(
        Guid id,
        [FromQuery] Guid? technicianId,
        [FromBody] SubmitRepairEstimateDto request,
        CancellationToken cancellationToken)
    {
        if (!TryGetAuthorizedUserId([UserRole.MaintenanceTechnician], out var currentUserId, out var authResult))
        {
            return authResult;
        }

        if (!RouteActorMatchesCurrentUser(technicianId, currentUserId))
        {
            return Forbid();
        }

        return await ExecuteAsync(
            () => maintenanceRequestService.SubmitEstimateAsync(
                id,
                currentUserId,
                request,
                cancellationToken),
            result => CreatedAtAction(nameof(GetLatestEstimate), new { id }, result));
    }

    [HttpPatch("{id:guid}/estimates/{estimateId:guid}/submit-for-review")]
    [ProducesResponseType<MaintenanceRequestResponseDto>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status409Conflict)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    public async Task<ActionResult<MaintenanceRequestResponseDto>> SubmitEstimateForReview(
        Guid id,
        Guid estimateId,
        CancellationToken cancellationToken)
    {
        if (!TryGetAuthorizedUserId([UserRole.MaintenanceTechnician], out var currentUserId, out var authResult))
        {
            return authResult;
        }

        return await ExecuteAsync(
            async () =>
            {
                var maintenanceRequest = await GetAuthorizedRequestAsync(id, currentUserId, cancellationToken);
                if (maintenanceRequest.TechnicianId != currentUserId)
                {
                    throw MaintenanceRequestServiceException.NotFound(
                        $"Maintenance request '{id}' was not found.");
                }

                return await maintenanceRequestService.SubmitEstimateForReviewAsync(
                    id,
                    estimateId,
                    cancellationToken);
            },
            result => Ok(result));
    }

    [HttpPatch("{id:guid}/estimates/{estimateId:guid}/approve")]
    [ProducesResponseType<RepairEstimateResponseDto>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status409Conflict)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    public async Task<ActionResult<RepairEstimateResponseDto>> ApproveEstimate(
        Guid id,
        Guid estimateId,
        [FromQuery] Guid? landlordId,
        [FromBody] ReviewRepairEstimateDto request,
        CancellationToken cancellationToken)
    {
        if (!TryGetAuthorizedUserId([UserRole.Landlord, UserRole.Admin], out var currentUserId, out var authResult))
        {
            return authResult;
        }

        if (!RouteActorMatchesCurrentUser(landlordId, currentUserId))
        {
            return Forbid();
        }

        return await ExecuteAsync(
            () => maintenanceRequestService.ApproveEstimateAsync(
                id,
                estimateId,
                currentUserId,
                request,
                cancellationToken),
            result => Ok(result));
    }

    [HttpPatch("{id:guid}/estimates/{estimateId:guid}/reject")]
    [ProducesResponseType<RepairEstimateResponseDto>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status409Conflict)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    public async Task<ActionResult<RepairEstimateResponseDto>> RejectEstimate(
        Guid id,
        Guid estimateId,
        [FromQuery] Guid? landlordId,
        [FromBody] ReviewRepairEstimateDto request,
        CancellationToken cancellationToken)
    {
        if (!TryGetAuthorizedUserId([UserRole.Landlord, UserRole.Admin], out var currentUserId, out var authResult))
        {
            return authResult;
        }

        if (!RouteActorMatchesCurrentUser(landlordId, currentUserId))
        {
            return Forbid();
        }

        return await ExecuteAsync(
            () => maintenanceRequestService.RejectEstimateAsync(
                id,
                estimateId,
                currentUserId,
                request,
                cancellationToken),
            result => Ok(result));
    }

    [HttpPatch("{id:guid}/estimates/{estimateId:guid}/request-revision")]
    [ProducesResponseType<RepairEstimateResponseDto>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status409Conflict)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    public async Task<ActionResult<RepairEstimateResponseDto>> RequestEstimateRevision(
        Guid id,
        Guid estimateId,
        [FromQuery] Guid? landlordId,
        [FromBody] ReviewRepairEstimateDto request,
        CancellationToken cancellationToken)
    {
        if (!TryGetAuthorizedUserId([UserRole.Landlord, UserRole.Admin], out var currentUserId, out var authResult))
        {
            return authResult;
        }

        if (!RouteActorMatchesCurrentUser(landlordId, currentUserId))
        {
            return Forbid();
        }

        return await ExecuteAsync(
            () => maintenanceRequestService.RequestEstimateRevisionAsync(
                id,
                estimateId,
                currentUserId,
                request,
                cancellationToken),
            result => Ok(result));
    }

    [HttpGet("{id:guid}/estimates")]
    [ProducesResponseType<IReadOnlyList<RepairEstimateResponseDto>>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    public async Task<ActionResult<IReadOnlyList<RepairEstimateResponseDto>>> GetEstimates(
        Guid id,
        CancellationToken cancellationToken)
    {
        if (!TryGetAuthorizedUserId(
                [UserRole.Tenant, UserRole.MaintenanceTechnician, UserRole.Landlord, UserRole.Admin],
                out var currentUserId,
                out var authResult))
        {
            return authResult;
        }

        return await ExecuteAsync(
            async () =>
            {
                await GetAuthorizedRequestAsync(id, currentUserId, cancellationToken);
                return await maintenanceRequestService.GetEstimatesAsync(id, cancellationToken);
            },
            result => Ok(result));
    }

    [HttpGet("{id:guid}/estimates/latest")]
    [ProducesResponseType<RepairEstimateResponseDto>(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    public async Task<ActionResult<RepairEstimateResponseDto?>> GetLatestEstimate(
        Guid id,
        CancellationToken cancellationToken)
    {
        if (!TryGetAuthorizedUserId(
                [UserRole.Tenant, UserRole.MaintenanceTechnician, UserRole.Landlord, UserRole.Admin],
                out var currentUserId,
                out var authResult))
        {
            return authResult;
        }

        return await ExecuteAsync(
            async () =>
            {
                await GetAuthorizedRequestAsync(id, currentUserId, cancellationToken);
                return await maintenanceRequestService.GetLatestEstimateAsync(id, cancellationToken);
            },
            result => result is null ? NoContent() : Ok(result));
    }

    [HttpPost("{id:guid}/attachments")]
    [Consumes("multipart/form-data")]
    [ProducesResponseType<MaintenanceAttachmentResponseDto>(StatusCodes.Status201Created)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    public async Task<ActionResult<MaintenanceAttachmentResponseDto>> UploadAttachment(
        Guid id,
        [FromQuery] Guid? tenantId,
        [FromForm] UploadMaintenanceAttachmentDto request,
        CancellationToken cancellationToken)
    {
        if (!TryGetAuthorizedUserId([UserRole.Tenant], out var currentUserId, out var authResult))
        {
            return authResult;
        }

        if (!RouteActorMatchesCurrentUser(tenantId, currentUserId))
        {
            return Forbid();
        }

        await using var content = request.File.OpenReadStream();
        return await ExecuteAsync(
            () => maintenanceAttachmentService.UploadAsync(id, currentUserId, content, request.File.FileName,
                request.File.ContentType, request.File.Length, request.AttachmentType, cancellationToken),
            result => CreatedAtAction(nameof(DownloadAttachment), new { id, attachmentId = result.Id, tenantId = currentUserId }, result));
    }

    [HttpGet("{id:guid}/attachments")]
    [ProducesResponseType<IReadOnlyList<MaintenanceAttachmentResponseDto>>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    public async Task<ActionResult<IReadOnlyList<MaintenanceAttachmentResponseDto>>> GetAttachments(
        Guid id, [FromQuery] Guid? tenantId, CancellationToken cancellationToken)
    {
        if (!TryGetAuthorizedUserId([UserRole.Tenant], out var currentUserId, out var authResult))
        {
            return authResult;
        }

        if (!RouteActorMatchesCurrentUser(tenantId, currentUserId))
        {
            return Forbid();
        }

        return await ExecuteAsync(
            () => maintenanceAttachmentService.GetByRequestAsync(id, currentUserId, cancellationToken),
            result => Ok(result));
    }

    [HttpGet("{id:guid}/attachments/{attachmentId:guid}")]
    [ProducesResponseType(StatusCodes.Status302Found)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    public async Task<IActionResult> DownloadAttachment(
        Guid id, Guid attachmentId, [FromQuery] Guid? tenantId, CancellationToken cancellationToken)
    {
        if (!TryGetAuthorizedUserId([UserRole.Tenant], out var currentUserId, out var authResult))
        {
            return authResult;
        }

        if (!RouteActorMatchesCurrentUser(tenantId, currentUserId))
        {
            return Forbid();
        }

        return await ExecuteAttachmentAsync(async () =>
            Redirect(await maintenanceAttachmentService.GenerateDownloadUrlAsync(
                id,
                attachmentId,
                currentUserId,
                cancellationToken)));
    }

    [HttpDelete("{id:guid}/attachments/{attachmentId:guid}")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    public async Task<IActionResult> DeleteAttachment(
        Guid id, Guid attachmentId, [FromQuery] Guid? tenantId, CancellationToken cancellationToken)
    {
        if (!TryGetAuthorizedUserId([UserRole.Tenant], out var currentUserId, out var authResult))
        {
            return authResult;
        }

        if (!RouteActorMatchesCurrentUser(tenantId, currentUserId))
        {
            return Forbid();
        }

        return await ExecuteAttachmentAsync(async () =>
        {
            await maintenanceAttachmentService.DeleteAsync(id, attachmentId, currentUserId, cancellationToken);
            return NoContent();
        });
    }

    private bool TryGetAuthorizedUserId(
        IReadOnlyCollection<UserRole> allowedRoles,
        out Guid userId,
        out ActionResult authResult)
    {
        userId = currentUserService.UserId ?? Guid.Empty;

        if (userId == Guid.Empty)
        {
            authResult = Unauthorized();
            return false;
        }

        if (currentUserService.Role is not { } role || !allowedRoles.Contains(role))
        {
            authResult = Forbid();
            return false;
        }

        authResult = Ok();
        return true;
    }

    private static bool RouteActorMatchesCurrentUser(Guid? routeActorId, Guid currentUserId) =>
        routeActorId is null || routeActorId == Guid.Empty || routeActorId == currentUserId;

    private async Task<MaintenanceRequestResponseDto> GetAuthorizedRequestAsync(
        Guid id,
        Guid currentUserId,
        CancellationToken cancellationToken)
    {
        var maintenanceRequest = await GetRequiredRequestAsync(id, cancellationToken);

        if (currentUserService.Role == UserRole.Tenant
            && maintenanceRequest.TenantId != currentUserId)
        {
            throw MaintenanceRequestServiceException.NotFound(
                $"Maintenance request '{id}' was not found.");
        }

        if (currentUserService.Role == UserRole.MaintenanceTechnician
            && maintenanceRequest.TechnicianId != currentUserId)
        {
            throw MaintenanceRequestServiceException.NotFound(
                $"Maintenance request '{id}' was not found.");
        }

        return maintenanceRequest;
    }

    private async Task<MaintenanceRequestResponseDto> GetRequiredRequestAsync(
        Guid id,
        CancellationToken cancellationToken)
    {
        return await maintenanceRequestService.GetByIdAsync(id, cancellationToken)
            ?? throw MaintenanceRequestServiceException.NotFound(
                $"Maintenance request '{id}' was not found.");
    }

    private async Task<ActionResult<T>> ExecuteAsync<T>(
        Func<Task<T>> operation,
        Func<T, ActionResult<T>> successResult)
    {
        try
        {
            var result = await operation();
            return successResult(result);
        }
        catch (MaintenanceRequestServiceException exception)
        {
            return MapServiceException(exception);
        }
        catch (MaintenanceCoordinationAgentClientException)
        {
            return Problem(
                statusCode: StatusCodes.Status502BadGateway,
                title: "Maintenance coordination agent unavailable.",
                detail: "The coordination analysis could not be completed.");
        }
        catch (OperationCanceledException) when (HttpContext.RequestAborted.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception exception)
        {
            logger.LogError(exception, "An unexpected error occurred while processing a maintenance request.");

            return Problem(
                statusCode: StatusCodes.Status500InternalServerError,
                title: "An unexpected error occurred.",
                detail: "The request could not be completed.");
        }
    }

    private async Task<IActionResult> ExecuteAttachmentAsync(Func<Task<IActionResult>> operation)
    {
        try { return await operation(); }
        catch (MaintenanceRequestServiceException exception) { return MapServiceException(exception); }
        catch (OperationCanceledException) when (HttpContext.RequestAborted.IsCancellationRequested) { throw; }
        catch (Exception exception)
        {
            logger.LogError(exception, "An unexpected error occurred while processing a maintenance attachment.");
            return Problem(statusCode: StatusCodes.Status500InternalServerError, title: "An unexpected error occurred.", detail: "The request could not be completed.");
        }
    }

    private ActionResult MapServiceException(MaintenanceRequestServiceException exception)
    {
        var (statusCode, title) = exception.Error switch
        {
            MaintenanceRequestServiceError.Validation =>
                (StatusCodes.Status400BadRequest, "Invalid maintenance request."),
            MaintenanceRequestServiceError.NotFound =>
                (StatusCodes.Status404NotFound, "Maintenance request not found."),
            MaintenanceRequestServiceError.Conflict =>
                (StatusCodes.Status409Conflict, "Maintenance request conflict."),
            _ =>
                (StatusCodes.Status500InternalServerError, "An unexpected error occurred.")
        };

        return StatusCode(statusCode, new ProblemDetails
        {
            Status = statusCode,
            Title = title,
            Detail = statusCode == StatusCodes.Status500InternalServerError
                ? "The request could not be completed."
                : exception.Message
        });
    }
}
