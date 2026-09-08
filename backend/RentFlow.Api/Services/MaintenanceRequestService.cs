using Microsoft.EntityFrameworkCore;
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
        ValidateRequestDetails(
            request.PropertyId,
            request.Title,
            request.Description,
            request.TenantAccessNotes);
        ValidateCategory(request.Category);
        ValidatePriority(request.Priority);

        var maintenanceRequest = new MaintenanceRequest
        {
            TenantId = tenantId,
            PropertyId = request.PropertyId,
            Title = request.Title.Trim(),
            Description = request.Description.Trim(),
            Category = request.Category,
            Priority = request.Priority,
            Status = MaintenanceRequestStatus.Submitted,
            TenantAccessNotes = NormalizeOptionalText(request.TenantAccessNotes),
            CreatedAt = DateTimeOffset.UtcNow
        };

        dbContext.MaintenanceRequests.Add(maintenanceRequest);
        await dbContext.SaveChangesAsync(cancellationToken);

        return MapToResponse(maintenanceRequest);
    }

    public async Task<MaintenanceRequestResponseDto?> GetByIdAsync(
        Guid requestId,
        CancellationToken cancellationToken = default)
    {
        ValidateRequestId(requestId);

        var maintenanceRequest = await dbContext.MaintenanceRequests
            .AsNoTracking()
            .SingleOrDefaultAsync(item => item.Id == requestId, cancellationToken);

        return maintenanceRequest is null ? null : MapToResponse(maintenanceRequest);
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

        return MapToResponse(maintenanceRequest);
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

        await dbContext.SaveChangesAsync(cancellationToken);

        return MapToResponse(maintenanceRequest);
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

        maintenanceRequest.TechnicianId = request.TechnicianId;
        maintenanceRequest.AssignmentNotes = NormalizeOptionalText(request.AssignmentNotes);
        maintenanceRequest.Status = MaintenanceRequestStatus.Assigned;
        maintenanceRequest.UpdatedAt = DateTimeOffset.UtcNow;

        await dbContext.SaveChangesAsync(cancellationToken);

        return MapToResponse(maintenanceRequest);
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

    private static string? NormalizeOptionalText(string? value) =>
        string.IsNullOrWhiteSpace(value) ? null : value.Trim();

    private static MaintenanceRequestResponseDto MapToResponse(MaintenanceRequest request)
    {
        return new MaintenanceRequestResponseDto
        {
            Id = request.Id,
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

    private static MaintenanceRequestSummaryDto MapToSummary(MaintenanceRequest request)
    {
        return new MaintenanceRequestSummaryDto
        {
            Id = request.Id,
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
}
