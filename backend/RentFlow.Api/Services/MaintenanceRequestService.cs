using Microsoft.EntityFrameworkCore;
using System.Text.RegularExpressions;
using RentFlow.Api.Data;
using RentFlow.Api.DTOs.Maintenance;
using RentFlow.Api.Models;
using RentFlow.Api.Services.Interfaces;

namespace RentFlow.Api.Services;

/// <summary>
/// Provides core maintenance request operations.
/// </summary>
public class MaintenanceRequestService(ApplicationDbContext dbContext) : IMaintenanceRequestService
{
    public async Task<MaintenanceRequestResponseDto> CreateAsync(
        Guid tenantId,
        CreateMaintenanceRequestDto request,
        CancellationToken cancellationToken = default)
    {
        ValidateTenantId(tenantId);
        ValidateCategory(request.Category);
        ValidatePriority(request.Priority);
        if (request.PreferredAccessWindow is not { } access || !Enum.IsDefined(access))
        {
            throw MaintenanceRequestServiceException.Validation("Choose a valid preferred access time.");
        }
        var title = string.IsNullOrWhiteSpace(request.Title)
            ? DeriveTitle(request.Description, request.Category)
            : request.Title.Trim();
        ValidateRequestDetails(
            request.PropertyId,
            title,
            request.Description,
            request.TenantAccessNotes);

        var today = DateOnly.FromDateTime(DateTime.UtcNow);
        if (!await TenantMaintenanceEligibility.EligibleProperties(dbContext, tenantId, today)
            .AnyAsync(property => property.Id == request.PropertyId, cancellationToken))
        {
            throw MaintenanceRequestServiceException.Forbidden(
                "You need a current active lease for this property to submit a maintenance request.");
        }

        var maintenanceRequest = new MaintenanceRequest
        {
            TenantId = tenantId,
            PropertyId = request.PropertyId,
            Title = title,
            Description = request.Description.Trim(),
            Category = request.Category,
            Priority = request.Priority,
            Status = MaintenanceRequestStatus.Submitted,
            TenantAccessNotes = NormalizeOptionalText(request.TenantAccessNotes),
            PreferredAccessWindow = access,
            CreatedAt = DateTimeOffset.UtcNow
        };

        dbContext.MaintenanceRequests.Add(maintenanceRequest);
        AddHistory(
            maintenanceRequest,
            fromStatus: null,
            toStatus: MaintenanceRequestStatus.Submitted,
            changedByUserId: tenantId,
            notes: "Maintenance request submitted.");
        await dbContext.SaveChangesAsync(cancellationToken);

        return await MapToResponseAsync(maintenanceRequest, cancellationToken);
    }

    private static string DeriveTitle(string? description, MaintenanceCategory category)
    {
        var normalized = Regex.Replace(description?.Trim() ?? string.Empty, @"\s+", " ");
        if (normalized.Length == 0) return $"{category} issue";
        var sentence = Regex.Match(normalized, @"^.*?[.!?](?=\s|$)");
        var title = sentence.Success ? sentence.Value.TrimEnd('.', '!', '?') : normalized;
        if (string.IsNullOrWhiteSpace(title)) return $"{category} issue";
        if (string.IsNullOrWhiteSpace(title)) return $"{category} issue";
        if (title.Length <= 200) return title;
        var boundary = title.LastIndexOf(' ', 199, 200);
        return title[..(boundary > 0 ? boundary : 200)].TrimEnd();
    }

    public async Task<MaintenanceRequestResponseDto?> GetByIdAsync(
        Guid requestId,
        CancellationToken cancellationToken = default)
    {
        ValidateRequestId(requestId);

        var maintenanceRequest = await dbContext.MaintenanceRequests
            .AsNoTracking()
            .SingleOrDefaultAsync(item => item.Id == requestId, cancellationToken);

        return maintenanceRequest is null ? null : await MapToResponseAsync(maintenanceRequest, cancellationToken, includeContact: true);
    }

    public async Task<IReadOnlyList<MaintenanceRequestSummaryDto>> GetByTenantAsync(
        Guid tenantId,
        CancellationToken cancellationToken = default)
    {
        ValidateTenantId(tenantId);

        var requests = await dbContext.MaintenanceRequests
            .AsNoTracking()
            .Where(item => item.TenantId == tenantId)
            .OrderByDescending(item => item.CreatedAt)
            .ToListAsync(cancellationToken);

        return requests.Select(MapToSummary).ToList();
    }

    public async Task<IReadOnlyList<MaintenanceRequestSummaryDto>> GetByPropertyAsync(
        Guid propertyId,
        CancellationToken cancellationToken = default)
    {
        ValidatePropertyId(propertyId);

        var requests = await dbContext.MaintenanceRequests
            .AsNoTracking()
            .Where(item => item.PropertyId == propertyId)
            .OrderByDescending(item => item.CreatedAt)
            .ToListAsync(cancellationToken);

        return requests.Select(MapToSummary).ToList();
    }

    public async Task<IReadOnlyList<MaintenanceRequestSummaryDto>> GetByTechnicianAsync(
        Guid technicianId,
        CancellationToken cancellationToken = default)
    {
        ValidateTechnicianId(technicianId);

        var requests = await dbContext.MaintenanceRequests
            .AsNoTracking()
            .Where(item => item.TechnicianId == technicianId)
            .OrderByDescending(item => item.CreatedAt)
            .ToListAsync(cancellationToken);

        return requests.Select(MapToSummary).ToList();
    }

    public async Task<IReadOnlyList<MaintenanceTechnicianChoiceDto>> GetTechnicianChoicesAsync(
        CancellationToken cancellationToken = default)
    {
        return await dbContext.Users
            .AsNoTracking()
            .Where(user =>
                user.Role == UserRole.MaintenanceTechnician
                && user.IsActive)
            .OrderBy(user => user.FullName)
            .ThenBy(user => user.Id)
            .Select(user => new MaintenanceTechnicianChoiceDto(
                user.Id,
                user.FullName))
            .ToListAsync(cancellationToken);
    }

    public async Task<IReadOnlyList<MaintenanceStatusHistoryResponseDto>> GetHistoryAsync(
        Guid requestId,
        CancellationToken cancellationToken = default)
    {
        ValidateRequestId(requestId);

        var requestExists = await dbContext.MaintenanceRequests
            .AsNoTracking()
            .AnyAsync(item => item.Id == requestId, cancellationToken);

        if (!requestExists)
        {
            throw MaintenanceRequestServiceException.NotFound(
                $"Maintenance request '{requestId}' was not found.");
        }

        var history = await dbContext.MaintenanceStatusHistories
            .AsNoTracking()
            .Where(item => item.MaintenanceRequestId == requestId)
            .OrderBy(item => item.ChangedAt)
            .ThenBy(item => item.Id)
            .ToListAsync(cancellationToken);

        return history.Select(MapToHistoryResponse).ToList();
    }

    public async Task<MaintenanceRequestResponseDto> UpdateTenantRequestAsync(
        Guid requestId,
        Guid tenantId,
        UpdateMaintenanceRequestDto request,
        CancellationToken cancellationToken = default)
    {
        ValidateRequestId(requestId);
        ValidateTenantId(tenantId);
        ValidateTenantEditableDetails(
            request.Title,
            request.Description,
            request.TenantAccessNotes);
        ValidateCategory(request.Category);
        ValidatePriority(request.Priority);

        var maintenanceRequest = await GetTenantRequestAsync(
            requestId,
            tenantId,
            cancellationToken);
        EnsureStatus(maintenanceRequest, "updated", MaintenanceRequestStatus.Submitted);

        maintenanceRequest.Title = request.Title.Trim();
        maintenanceRequest.Description = request.Description.Trim();
        maintenanceRequest.Category = request.Category;
        maintenanceRequest.Priority = request.Priority;
        maintenanceRequest.TenantAccessNotes = NormalizeOptionalText(request.TenantAccessNotes);
        maintenanceRequest.UpdatedAt = DateTimeOffset.UtcNow;

        await dbContext.SaveChangesAsync(cancellationToken);

        return await MapToResponseAsync(maintenanceRequest, cancellationToken);
    }

    public async Task<MaintenanceRequestResponseDto> TriageAsync(
        Guid requestId,
        TriageMaintenanceRequestDto request,
        CancellationToken cancellationToken = default)
    {
        ValidateRequestId(requestId);
        ValidateCategory(request.Category);
        ValidatePriority(request.Priority);
        ValidateMaxLength(request.TriageNotes, 2000, "Triage notes");

        var maintenanceRequest = await GetTrackedRequestAsync(requestId, cancellationToken);
        EnsureStatus(maintenanceRequest, "triaged", MaintenanceRequestStatus.Submitted);

        maintenanceRequest.Category = request.Category;
        maintenanceRequest.Priority = request.Priority;
        maintenanceRequest.TriageNotes = NormalizeOptionalText(request.TriageNotes);
        maintenanceRequest.Status = MaintenanceRequestStatus.Triaged;
        maintenanceRequest.UpdatedAt = DateTimeOffset.UtcNow;
        AddHistory(
            maintenanceRequest,
            fromStatus: MaintenanceRequestStatus.Submitted,
            toStatus: MaintenanceRequestStatus.Triaged,
            changedByUserId: null,
            notes: maintenanceRequest.TriageNotes);

        await dbContext.SaveChangesAsync(cancellationToken);

        return await MapToResponseAsync(maintenanceRequest, cancellationToken);
    }

    public async Task<MaintenanceRequestResponseDto> AssignTechnicianAsync(
        Guid requestId,
        AssignTechnicianDto request,
        CancellationToken cancellationToken = default)
    {
        ValidateRequestId(requestId);

        if (request.TechnicianId == Guid.Empty)
        {
            throw MaintenanceRequestServiceException.Validation("A technician ID is required.");
        }

        ValidateMaxLength(request.AssignmentNotes, 2000, "Assignment notes");

        var maintenanceRequest = await GetTrackedRequestAsync(requestId, cancellationToken);
        EnsureStatus(maintenanceRequest, "assigned", MaintenanceRequestStatus.Triaged);

        if (!await dbContext.Users.AsNoTracking().AnyAsync(user =>
            user.Id == request.TechnicianId && user.IsActive && user.Role == UserRole.MaintenanceTechnician,
            cancellationToken))
            throw MaintenanceRequestServiceException.Validation("Choose an active maintenance technician.");

        maintenanceRequest.TechnicianId = request.TechnicianId;
        maintenanceRequest.AssignmentNotes = NormalizeOptionalText(request.AssignmentNotes);
        maintenanceRequest.Status = MaintenanceRequestStatus.Assigned;
        maintenanceRequest.UpdatedAt = DateTimeOffset.UtcNow;
        AddHistory(
            maintenanceRequest,
            fromStatus: MaintenanceRequestStatus.Triaged,
            toStatus: MaintenanceRequestStatus.Assigned,
            changedByUserId: null,
            notes: maintenanceRequest.AssignmentNotes);

        await dbContext.SaveChangesAsync(cancellationToken);

        return await MapToResponseAsync(maintenanceRequest, cancellationToken);
    }

    public async Task<MaintenanceRequestResponseDto> MarkEstimatePendingAsync(
        Guid requestId,
        CancellationToken cancellationToken = default)
    {
        ValidateRequestId(requestId);

        var maintenanceRequest = await GetTrackedRequestAsync(requestId, cancellationToken);
        EnsureStatus(maintenanceRequest, "prepared for an estimate", MaintenanceRequestStatus.Assigned);

        maintenanceRequest.Status = MaintenanceRequestStatus.EstimatePending;
        maintenanceRequest.UpdatedAt = DateTimeOffset.UtcNow;
        AddHistory(
            maintenanceRequest,
            MaintenanceRequestStatus.Assigned,
            MaintenanceRequestStatus.EstimatePending,
            maintenanceRequest.TechnicianId,
            "Technician estimate requested.");

        await dbContext.SaveChangesAsync(cancellationToken);
        return await MapToResponseAsync(maintenanceRequest, cancellationToken);
    }

    public async Task<RepairEstimateResponseDto> SubmitEstimateAsync(
        Guid requestId,
        Guid technicianId,
        SubmitRepairEstimateDto request,
        CancellationToken cancellationToken = default)
    {
        ValidateRequestId(requestId);
        ValidateTechnicianId(technicianId);
        ValidateEstimateSubmission(request);

        var maintenanceRequest = await GetTrackedRequestAsync(requestId, cancellationToken);
        EnsureStatus(maintenanceRequest, "submitted for estimation", MaintenanceRequestStatus.EstimatePending);

        if (maintenanceRequest.TechnicianId != technicianId)
        {
            throw MaintenanceRequestServiceException.Conflict(
                "Only the assigned technician can submit a repair estimate.");
        }

        var now = DateTimeOffset.UtcNow;
        var latestVersion = await dbContext.RepairEstimates
            .Where(estimate => estimate.MaintenanceRequestId == requestId)
            .Select(estimate => (int?)estimate.VersionNumber)
            .MaxAsync(cancellationToken) ?? 0;

        var estimate = new RepairEstimate
        {
            MaintenanceRequestId = requestId,
            TechnicianId = technicianId,
            VersionNumber = latestVersion + 1,
            LaborCost = request.LaborCost,
            PartsCost = request.PartsCost,
            AdditionalCost = request.AdditionalCost,
            TotalCost = CalculateTotalCost(request.LaborCost, request.PartsCost, request.AdditionalCost),
            Notes = NormalizeOptionalText(request.Notes),
            Status = RepairEstimateStatus.Submitted,
            CreatedAt = now,
            SubmittedAt = now
        };

        dbContext.RepairEstimates.Add(estimate);
        maintenanceRequest.Status = MaintenanceRequestStatus.EstimateSubmitted;
        maintenanceRequest.UpdatedAt = now;
        AddHistory(
            maintenanceRequest,
            MaintenanceRequestStatus.EstimatePending,
            MaintenanceRequestStatus.EstimateSubmitted,
            technicianId,
            "Repair estimate submitted.");

        await dbContext.SaveChangesAsync(cancellationToken);
        return MapToEstimateResponse(estimate);
    }

    public async Task<MaintenanceRequestResponseDto> SubmitEstimateForReviewAsync(
        Guid requestId,
        Guid estimateId,
        CancellationToken cancellationToken = default)
    {
        ValidateRequestId(requestId);
        ValidateEstimateId(estimateId);

        var maintenanceRequest = await GetTrackedRequestAsync(requestId, cancellationToken);
        EnsureStatus(maintenanceRequest, "sent for landlord approval", MaintenanceRequestStatus.EstimateSubmitted);
        var estimate = await GetTrackedEstimateAsync(requestId, estimateId, cancellationToken);

        EnsureEstimateStatus(estimate, "sent for landlord approval", RepairEstimateStatus.Submitted);

        maintenanceRequest.Status = MaintenanceRequestStatus.AwaitingLandlordApproval;
        maintenanceRequest.UpdatedAt = DateTimeOffset.UtcNow;
        AddHistory(
            maintenanceRequest,
            MaintenanceRequestStatus.EstimateSubmitted,
            MaintenanceRequestStatus.AwaitingLandlordApproval,
            estimate.TechnicianId,
            "Repair estimate submitted for landlord approval.");

        await dbContext.SaveChangesAsync(cancellationToken);
        return await MapToResponseAsync(maintenanceRequest, cancellationToken);
    }

    public Task<RepairEstimateResponseDto> ApproveEstimateAsync(
        Guid requestId,
        Guid estimateId,
        Guid landlordId,
        ReviewRepairEstimateDto request,
        CancellationToken cancellationToken = default) =>
        ReviewEstimateAsync(
            requestId,
            estimateId,
            landlordId,
            request,
            RepairEstimateStatus.Approved,
            MaintenanceRequestStatus.Approved,
            false,
            cancellationToken);

    public Task<RepairEstimateResponseDto> RejectEstimateAsync(
        Guid requestId,
        Guid estimateId,
        Guid landlordId,
        ReviewRepairEstimateDto request,
        CancellationToken cancellationToken = default) =>
        ReviewEstimateAsync(
            requestId,
            estimateId,
            landlordId,
            request,
            RepairEstimateStatus.Rejected,
            MaintenanceRequestStatus.Rejected,
            true,
            cancellationToken);

    public Task<RepairEstimateResponseDto> RequestEstimateRevisionAsync(
        Guid requestId,
        Guid estimateId,
        Guid landlordId,
        ReviewRepairEstimateDto request,
        CancellationToken cancellationToken = default) =>
        ReviewEstimateAsync(
            requestId,
            estimateId,
            landlordId,
            request,
            RepairEstimateStatus.RevisionRequested,
            MaintenanceRequestStatus.EstimatePending,
            true,
            cancellationToken);

    public async Task<MaintenanceRequestResponseDto> StartWorkAsync(
        Guid requestId,
        Guid technicianId,
        CancellationToken cancellationToken = default)
    {
        ValidateRequestId(requestId);
        ValidateTechnicianId(technicianId);

        var maintenanceRequest = await GetTrackedRequestAsync(requestId, cancellationToken);
        EnsureStatus(maintenanceRequest, "start work", MaintenanceRequestStatus.Approved);

        if (maintenanceRequest.TechnicianId != technicianId)
        {
            throw MaintenanceRequestServiceException.Conflict(
                "Only the assigned technician can start work on this maintenance request.");
        }

        var now = DateTimeOffset.UtcNow;
        maintenanceRequest.Status = MaintenanceRequestStatus.InProgress;
        maintenanceRequest.UpdatedAt = now;
        AddHistory(
            maintenanceRequest,
            MaintenanceRequestStatus.Approved,
            MaintenanceRequestStatus.InProgress,
            technicianId,
            "Work started.");

        await dbContext.SaveChangesAsync(cancellationToken);
        return await MapToResponseAsync(maintenanceRequest, cancellationToken);
    }

    public async Task<MaintenanceRequestResponseDto> CompleteWorkAsync(
        Guid requestId,
        Guid technicianId,
        CancellationToken cancellationToken = default)
    {
        ValidateRequestId(requestId);
        ValidateTechnicianId(technicianId);

        var maintenanceRequest = await GetTrackedRequestAsync(requestId, cancellationToken);
        EnsureStatus(maintenanceRequest, "complete work", MaintenanceRequestStatus.InProgress);

        if (maintenanceRequest.TechnicianId != technicianId)
        {
            throw MaintenanceRequestServiceException.Conflict(
                "Only the assigned technician can complete work on this maintenance request.");
        }

        var now = DateTimeOffset.UtcNow;
        maintenanceRequest.Status = MaintenanceRequestStatus.Completed;
        maintenanceRequest.CompletedAt = now;
        maintenanceRequest.UpdatedAt = now;
        AddHistory(
            maintenanceRequest,
            MaintenanceRequestStatus.InProgress,
            MaintenanceRequestStatus.Completed,
            technicianId,
            "Work completed.");

        await dbContext.SaveChangesAsync(cancellationToken);
        return await MapToResponseAsync(maintenanceRequest, cancellationToken);
    }

    public async Task<IReadOnlyList<RepairEstimateResponseDto>> GetEstimatesAsync(
        Guid requestId,
        CancellationToken cancellationToken = default)
    {
        ValidateRequestId(requestId);
        await EnsureRequestExistsAsync(requestId, cancellationToken);

        var estimates = await dbContext.RepairEstimates
            .AsNoTracking()
            .Where(estimate => estimate.MaintenanceRequestId == requestId)
            .OrderBy(estimate => estimate.CreatedAt)
            .ThenBy(estimate => estimate.VersionNumber)
            .ToListAsync(cancellationToken);

        return estimates.Select(MapToEstimateResponse).ToList();
    }

    public async Task<RepairEstimateResponseDto?> GetLatestEstimateAsync(
        Guid requestId,
        CancellationToken cancellationToken = default)
    {
        ValidateRequestId(requestId);
        await EnsureRequestExistsAsync(requestId, cancellationToken);

        var estimate = await dbContext.RepairEstimates
            .AsNoTracking()
            .Where(item => item.MaintenanceRequestId == requestId)
            .OrderByDescending(item => item.VersionNumber)
            .ThenByDescending(item => item.CreatedAt)
            .FirstOrDefaultAsync(cancellationToken);

        return estimate is null ? null : MapToEstimateResponse(estimate);
    }

    private async Task<RepairEstimateResponseDto> ReviewEstimateAsync(
        Guid requestId,
        Guid estimateId,
        Guid landlordId,
        ReviewRepairEstimateDto request,
        RepairEstimateStatus estimateStatus,
        MaintenanceRequestStatus requestStatus,
        bool requiresReviewNotes,
        CancellationToken cancellationToken)
    {
        ValidateRequestId(requestId);
        ValidateEstimateId(estimateId);
        ValidateLandlordId(landlordId);
        ValidateReviewNotes(request.ReviewNotes, requiresReviewNotes);

        var maintenanceRequest = await GetTrackedRequestAsync(requestId, cancellationToken);
        EnsureStatus(
            maintenanceRequest,
            "reviewed",
            MaintenanceRequestStatus.AwaitingLandlordApproval);
        var estimate = await GetTrackedEstimateAsync(requestId, estimateId, cancellationToken);
        EnsureEstimateStatus(estimate, "reviewed", RepairEstimateStatus.Submitted);

        var now = DateTimeOffset.UtcNow;
        estimate.Status = estimateStatus;
        estimate.ReviewNotes = NormalizeOptionalText(request.ReviewNotes);
        estimate.ReviewedByUserId = landlordId;
        estimate.ReviewedAt = now;
        estimate.UpdatedAt = now;
        maintenanceRequest.Status = requestStatus;
        maintenanceRequest.UpdatedAt = now;
        AddHistory(
            maintenanceRequest,
            MaintenanceRequestStatus.AwaitingLandlordApproval,
            requestStatus,
            landlordId,
            estimate.ReviewNotes);

        await dbContext.SaveChangesAsync(cancellationToken);
        return MapToEstimateResponse(estimate);
    }

    private async Task<MaintenanceRequest> GetTenantRequestAsync(
        Guid requestId,
        Guid tenantId,
        CancellationToken cancellationToken)
    {
        var maintenanceRequest = await dbContext.MaintenanceRequests.SingleOrDefaultAsync(
            item => item.Id == requestId && item.TenantId == tenantId,
            cancellationToken);

        return maintenanceRequest
            ?? throw MaintenanceRequestServiceException.NotFound(
                "The maintenance request was not found for this tenant.");
    }

    private async Task<MaintenanceRequest> GetTrackedRequestAsync(
        Guid requestId,
        CancellationToken cancellationToken)
    {
        var maintenanceRequest = await dbContext.MaintenanceRequests.SingleOrDefaultAsync(
            item => item.Id == requestId,
            cancellationToken);

        return maintenanceRequest
            ?? throw MaintenanceRequestServiceException.NotFound(
                $"Maintenance request '{requestId}' was not found.");
    }

    private async Task<RepairEstimate> GetTrackedEstimateAsync(
        Guid requestId,
        Guid estimateId,
        CancellationToken cancellationToken)
    {
        var estimate = await dbContext.RepairEstimates.SingleOrDefaultAsync(
            item => item.Id == estimateId && item.MaintenanceRequestId == requestId,
            cancellationToken);

        return estimate
            ?? throw MaintenanceRequestServiceException.NotFound(
                $"Repair estimate '{estimateId}' was not found for maintenance request '{requestId}'.");
    }

    private async Task EnsureRequestExistsAsync(Guid requestId, CancellationToken cancellationToken)
    {
        var requestExists = await dbContext.MaintenanceRequests
            .AsNoTracking()
            .AnyAsync(item => item.Id == requestId, cancellationToken);

        if (!requestExists)
        {
            throw MaintenanceRequestServiceException.NotFound(
                $"Maintenance request '{requestId}' was not found.");
        }
    }

    private static void ValidateRequestDetails(
        Guid propertyId,
        string title,
        string description,
        string? tenantAccessNotes)
    {
        ValidatePropertyId(propertyId);
        ValidateTenantEditableDetails(title, description, tenantAccessNotes);
    }

    private static void ValidateTenantEditableDetails(
        string title,
        string description,
        string? tenantAccessNotes)
    {
        if (string.IsNullOrWhiteSpace(title))
        {
            throw MaintenanceRequestServiceException.Validation("Title is required.");
        }

        ValidateMaxLength(title, 200, "Title");

        if (string.IsNullOrWhiteSpace(description))
        {
            throw MaintenanceRequestServiceException.Validation("Description is required.");
        }

        ValidateMaxLength(description, 4000, "Description");
        ValidateMaxLength(tenantAccessNotes, 1000, "Tenant access notes");
    }

    private static void ValidateRequestId(Guid requestId)
    {
        if (requestId == Guid.Empty)
        {
            throw MaintenanceRequestServiceException.Validation("A maintenance request ID is required.");
        }
    }

    private static void ValidateTenantId(Guid tenantId)
    {
        if (tenantId == Guid.Empty)
        {
            throw MaintenanceRequestServiceException.Validation("A tenant ID is required.");
        }
    }

    private static void ValidateTechnicianId(Guid technicianId)
    {
        if (technicianId == Guid.Empty)
        {
            throw MaintenanceRequestServiceException.Validation("A technician ID is required.");
        }
    }

    private static void ValidateLandlordId(Guid landlordId)
    {
        if (landlordId == Guid.Empty)
        {
            throw MaintenanceRequestServiceException.Validation("A landlord ID is required.");
        }
    }

    private static void ValidateEstimateId(Guid estimateId)
    {
        if (estimateId == Guid.Empty)
        {
            throw MaintenanceRequestServiceException.Validation("A repair estimate ID is required.");
        }
    }

    private static void ValidatePropertyId(Guid propertyId)
    {
        if (propertyId == Guid.Empty)
        {
            throw MaintenanceRequestServiceException.Validation("A property ID is required.");
        }
    }

    private static void ValidateCategory(MaintenanceCategory category)
    {
        if (!Enum.IsDefined(category))
        {
            throw MaintenanceRequestServiceException.Validation("A valid maintenance category is required.");
        }
    }

    private static void ValidatePriority(MaintenancePriority priority)
    {
        if (!Enum.IsDefined(priority))
        {
            throw MaintenanceRequestServiceException.Validation("A valid maintenance priority is required.");
        }
    }

    private static void ValidateMaxLength(string? value, int maximumLength, string fieldName)
    {
        if (value is { Length: > 0 } && value.Length > maximumLength)
        {
            throw MaintenanceRequestServiceException.Validation(
                $"{fieldName} cannot exceed {maximumLength} characters.");
        }
    }

    private static void ValidateEstimateSubmission(SubmitRepairEstimateDto request)
    {
        if (request.LaborCost < 0 || request.PartsCost < 0 || request.AdditionalCost < 0)
        {
            throw MaintenanceRequestServiceException.Validation(
                "Repair estimate costs cannot be negative.");
        }

        ValidateMaxLength(request.Notes, 4000, "Estimate notes");
    }

    private static void ValidateReviewNotes(string? reviewNotes, bool required)
    {
        if (required && string.IsNullOrWhiteSpace(reviewNotes))
        {
            throw MaintenanceRequestServiceException.Validation(
                "Review notes are required for rejection or revision requests.");
        }

        ValidateMaxLength(reviewNotes, 2000, "Review notes");
    }

    private static decimal CalculateTotalCost(decimal laborCost, decimal partsCost, decimal additionalCost)
    {
        try
        {
            return checked(laborCost + partsCost + additionalCost);
        }
        catch (OverflowException)
        {
            throw MaintenanceRequestServiceException.Validation(
                "Repair estimate total cost is outside the supported range.");
        }
    }

    private static void EnsureStatus(
        MaintenanceRequest maintenanceRequest,
        string action,
        params MaintenanceRequestStatus[] allowedStatuses)
    {
        if (!allowedStatuses.Contains(maintenanceRequest.Status))
        {
            throw MaintenanceRequestServiceException.Conflict(
                $"A {maintenanceRequest.Status} maintenance request cannot be {action}.");
        }
    }

    private static void EnsureEstimateStatus(
        RepairEstimate estimate,
        string action,
        params RepairEstimateStatus[] allowedStatuses)
    {
        if (!allowedStatuses.Contains(estimate.Status))
        {
            throw MaintenanceRequestServiceException.Conflict(
                $"A {estimate.Status} repair estimate cannot be {action}.");
        }
    }

    private static string? NormalizeOptionalText(string? value) =>
        string.IsNullOrWhiteSpace(value) ? null : value.Trim();

    private void AddHistory(
        MaintenanceRequest maintenanceRequest,
        MaintenanceRequestStatus? fromStatus,
        MaintenanceRequestStatus toStatus,
        Guid? changedByUserId,
        string? notes)
    {
        dbContext.MaintenanceStatusHistories.Add(new MaintenanceStatusHistory
        {
            MaintenanceRequest = maintenanceRequest,
            FromStatus = fromStatus,
            ToStatus = toStatus,
            ChangedByUserId = changedByUserId,
            ChangedAt = DateTimeOffset.UtcNow,
            Notes = NormalizeOptionalText(notes)
        });
    }

    private async Task<MaintenanceRequestResponseDto> MapToResponseAsync(
        MaintenanceRequest request,
        CancellationToken cancellationToken,
        bool includeContact = false)
    {
        var response = MapToResponse(request);
        if (request.TechnicianId is { } technicianId)
        {
            // Project display identity only; account contact and profile data stay private.
            var identity = await dbContext.Users.AsNoTracking()
                .Where(user => user.Id == technicianId && user.Role == UserRole.MaintenanceTechnician)
                .Select(user => new { user.FullName, user.MaintenanceContactPhone, user.MaintenanceContactEnabled, user.IsActive })
                .SingleOrDefaultAsync(cancellationToken);
            response.AssignedTechnicianName = NormalizeOptionalText(identity?.FullName);
            if (includeContact && identity is { MaintenanceContactEnabled: true, IsActive: true })
                response.AssignedTechnicianContactPhone = PhoneNumberValidation.UsablePhoneNumber(identity.MaintenanceContactPhone);
        }

        return response;
    }

    private static MaintenanceRequestResponseDto MapToResponse(MaintenanceRequest request)
    {
        return new MaintenanceRequestResponseDto
        {
            Id = request.Id,
            ReferenceCode = string.IsNullOrEmpty(request.ReferenceCode)
                ? MaintenanceReferenceCode.FromId(request.Id) : request.ReferenceCode,
            PreferredAccessWindow = request.PreferredAccessWindow,
            PropertyId = request.PropertyId,
            TenantId = request.TenantId,
            TechnicianId = request.TechnicianId,
            Title = request.Title,
            Description = request.Description,
            Category = request.Category,
            Priority = request.Priority,
            Status = request.Status,
            TenantAccessNotes = request.TenantAccessNotes,
            TriageNotes = request.TriageNotes,
            AssignmentNotes = request.AssignmentNotes,
            CancellationReason = request.CancellationReason,
            CompletedAt = request.CompletedAt,
            CreatedAt = request.CreatedAt,
            UpdatedAt = request.UpdatedAt
        };
    }

    private static RepairEstimateResponseDto MapToEstimateResponse(RepairEstimate estimate)
    {
        return new RepairEstimateResponseDto
        {
            Id = estimate.Id,
            MaintenanceRequestId = estimate.MaintenanceRequestId,
            TechnicianId = estimate.TechnicianId,
            VersionNumber = estimate.VersionNumber,
            LaborCost = estimate.LaborCost,
            PartsCost = estimate.PartsCost,
            AdditionalCost = estimate.AdditionalCost,
            TotalCost = estimate.TotalCost,
            Notes = estimate.Notes,
            Status = estimate.Status,
            CreatedAt = estimate.CreatedAt,
            SubmittedAt = estimate.SubmittedAt,
            ReviewedAt = estimate.ReviewedAt,
            ReviewNotes = estimate.ReviewNotes
        };
    }

    private static MaintenanceRequestSummaryDto MapToSummary(MaintenanceRequest request)
    {
        return new MaintenanceRequestSummaryDto
        {
            Id = request.Id,
            ReferenceCode = string.IsNullOrEmpty(request.ReferenceCode)
                ? MaintenanceReferenceCode.FromId(request.Id) : request.ReferenceCode,
            PreferredAccessWindow = request.PreferredAccessWindow,
            PropertyId = request.PropertyId,
            TenantId = request.TenantId,
            TechnicianId = request.TechnicianId,
            Title = request.Title,
            Category = request.Category,
            Priority = request.Priority,
            Status = request.Status,
            CreatedAt = request.CreatedAt,
            UpdatedAt = request.UpdatedAt
        };
    }

    private static MaintenanceStatusHistoryResponseDto MapToHistoryResponse(
        MaintenanceStatusHistory history)
    {
        return new MaintenanceStatusHistoryResponseDto
        {
            Id = history.Id,
            FromStatus = history.FromStatus,
            ToStatus = history.ToStatus,
            ChangedByUserId = history.ChangedByUserId,
            ChangedAt = history.ChangedAt,
            Notes = history.Notes
        };
    }
}
