using Microsoft.EntityFrameworkCore;
using RentFlow.Api.Data;
using RentFlow.Api.DTOs.RentalApplications;
using RentFlow.Api.Models;
using RentFlow.Api.Services.Interfaces;

namespace RentFlow.Api.Services;

/// <summary>
/// Provides rental application operations.
/// </summary>
public class RentalApplicationService(ApplicationDbContext dbContext) : IRentalApplicationService
{
    private static readonly RentalApplicationStatus[] ActiveStatuses =
    [
        RentalApplicationStatus.Draft,
        RentalApplicationStatus.Submitted,
        RentalApplicationStatus.UnderReview,
        RentalApplicationStatus.ChangesRequested
    ];

    public async Task<RentalApplicationResponseDto> CreateAsync(
        Guid tenantId,
        CreateRentalApplicationDto request,
        CancellationToken cancellationToken = default)
    {
        ValidateTenantId(tenantId);
        ValidateApplicationDetails(
            request.PropertyId,
            request.MoveInDate,
            request.MonthlyIncome,
            request.Occupation,
            request.NumberOfOccupants);

        await EnsureNoActiveApplicationAsync(
            tenantId,
            request.PropertyId,
            applicationIdToExclude: null,
            cancellationToken);

        var now = DateTimeOffset.UtcNow;
        var application = new RentalApplication
        {
            TenantId = tenantId,
            PropertyId = request.PropertyId,
            MoveInDate = request.MoveInDate,
            MonthlyIncome = request.MonthlyIncome,
            Occupation = request.Occupation.Trim(),
            NumberOfOccupants = request.NumberOfOccupants,
            TenantNote = NormalizeOptionalText(request.TenantNote),
            Status = RentalApplicationStatus.Draft,
            CreatedAt = now
        };

        dbContext.RentalApplications.Add(application);
        await dbContext.SaveChangesAsync(cancellationToken);

        return MapToResponse(application);
    }

    public async Task<RentalApplicationResponseDto?> GetByIdAsync(
        Guid applicationId,
        CancellationToken cancellationToken = default)
    {
        var application = await dbContext.RentalApplications
            .AsNoTracking()
            .SingleOrDefaultAsync(item => item.Id == applicationId, cancellationToken);

        return application is null ? null : MapToResponse(application);
    }

    public async Task<RentalApplicationResponseDto?> GetByIdForTenantAsync(
        Guid applicationId,
        Guid tenantId,
        CancellationToken cancellationToken = default)
    {
        var application = await dbContext.RentalApplications
            .AsNoTracking()
            .SingleOrDefaultAsync(
                item => item.Id == applicationId && item.TenantId == tenantId,
                cancellationToken);

        return application is null ? null : MapToResponse(application);
    }

    public async Task<IReadOnlyList<RentalApplicationResponseDto>> GetByTenantAsync(
        Guid tenantId,
        CancellationToken cancellationToken = default)
    {
        ValidateTenantId(tenantId);

        var applications = await dbContext.RentalApplications
            .AsNoTracking()
            .Where(application => application.TenantId == tenantId)
            .OrderByDescending(application => application.CreatedAt)
            .ToListAsync(cancellationToken);

        return applications.Select(MapToResponse).ToList();
    }

    public async Task<IReadOnlyList<RentalApplicationResponseDto>> GetByPropertyAsync(
        Guid propertyId,
        CancellationToken cancellationToken = default)
    {
        if (propertyId == Guid.Empty)
        {
            throw RentalApplicationServiceException.Validation("A property ID is required.");
        }

        var applications = await dbContext.RentalApplications
            .AsNoTracking()
            .Where(application => application.PropertyId == propertyId)
            .OrderByDescending(application => application.CreatedAt)
            .ToListAsync(cancellationToken);

        return applications.Select(MapToResponse).ToList();
    }

    public async Task<RentalApplicationResponseDto> UpdateAsync(
        Guid applicationId,
        Guid tenantId,
        UpdateRentalApplicationDto request,
        CancellationToken cancellationToken = default)
    {
        ValidateTenantId(tenantId);

        var application = await GetTenantApplicationAsync(
            applicationId,
            tenantId,
            cancellationToken);

        EnsureStatus(
            application,
            "edited",
            RentalApplicationStatus.Draft,
            RentalApplicationStatus.ChangesRequested);

        ValidateApplicationDetails(
            application.PropertyId,
            request.MoveInDate,
            request.MonthlyIncome,
            request.Occupation,
            request.NumberOfOccupants);

        application.MoveInDate = request.MoveInDate;
        application.MonthlyIncome = request.MonthlyIncome;
        application.Occupation = request.Occupation.Trim();
        application.NumberOfOccupants = request.NumberOfOccupants;
        application.TenantNote = NormalizeOptionalText(request.TenantNote);
        application.UpdatedAt = DateTimeOffset.UtcNow;

        await dbContext.SaveChangesAsync(cancellationToken);

        return MapToResponse(application);
    }

    public async Task<RentalApplicationResponseDto> SubmitAsync(
        Guid applicationId,
        Guid tenantId,
        CancellationToken cancellationToken = default)
    {
        ValidateTenantId(tenantId);

        var application = await GetTenantApplicationAsync(
            applicationId,
            tenantId,
            cancellationToken);

        EnsureStatus(
            application,
            "submitted",
            RentalApplicationStatus.Draft,
            RentalApplicationStatus.ChangesRequested);

        ValidateApplicationDetails(
            application.PropertyId,
            application.MoveInDate,
            application.MonthlyIncome,
            application.Occupation,
            application.NumberOfOccupants);

        await EnsureNoActiveApplicationAsync(
            application.TenantId,
            application.PropertyId,
            application.Id,
            cancellationToken);

        var now = DateTimeOffset.UtcNow;
        application.Status = RentalApplicationStatus.Submitted;
        application.SubmittedAt = now;
        application.UpdatedAt = now;

        await dbContext.SaveChangesAsync(cancellationToken);

        return MapToResponse(application);
    }

    public async Task<RentalApplicationResponseDto> MarkUnderReviewAsync(
        Guid applicationId,
        CancellationToken cancellationToken = default)
    {
        var application = await GetTrackedApplicationAsync(applicationId, cancellationToken);
        EnsureStatus(application, "marked as under review", RentalApplicationStatus.Submitted);

        application.Status = RentalApplicationStatus.UnderReview;
        application.UpdatedAt = DateTimeOffset.UtcNow;

        await dbContext.SaveChangesAsync(cancellationToken);

        return MapToResponse(application);
    }

    public Task<RentalApplicationResponseDto> ApproveAsync(
        Guid applicationId,
        string? landlordResponse = null,
        CancellationToken cancellationToken = default)
    {
        return ApplyLandlordDecisionAsync(
            applicationId,
            RentalApplicationStatus.Approved,
            landlordResponse,
            cancellationToken);
    }

    public Task<RentalApplicationResponseDto> RejectAsync(
        Guid applicationId,
        string landlordReason,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(landlordReason))
        {
            throw RentalApplicationServiceException.Validation(
                "A landlord reason is required when rejecting an application.");
        }

        return ApplyLandlordDecisionAsync(
            applicationId,
            RentalApplicationStatus.Rejected,
            landlordReason,
            cancellationToken);
    }

    public Task<RentalApplicationResponseDto> RequestChangesAsync(
        Guid applicationId,
        string landlordMessage,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(landlordMessage))
        {
            throw RentalApplicationServiceException.Validation(
                "A landlord message is required when requesting changes.");
        }

        return ApplyLandlordDecisionAsync(
            applicationId,
            RentalApplicationStatus.ChangesRequested,
            landlordMessage,
            cancellationToken);
    }

    public async Task<RentalApplicationResponseDto> WithdrawAsync(
        Guid applicationId,
        Guid tenantId,
        CancellationToken cancellationToken = default)
    {
        ValidateTenantId(tenantId);

        var application = await GetTenantApplicationAsync(
            applicationId,
            tenantId,
            cancellationToken);

        EnsureStatus(
            application,
            "withdrawn",
            RentalApplicationStatus.Draft,
            RentalApplicationStatus.Submitted,
            RentalApplicationStatus.UnderReview,
            RentalApplicationStatus.ChangesRequested);

        application.Status = RentalApplicationStatus.Withdrawn;
        application.UpdatedAt = DateTimeOffset.UtcNow;

        await dbContext.SaveChangesAsync(cancellationToken);

        return MapToResponse(application);
    }

    private async Task<RentalApplicationResponseDto> ApplyLandlordDecisionAsync(
        Guid applicationId,
        RentalApplicationStatus targetStatus,
        string? landlordResponse,
        CancellationToken cancellationToken)
    {
        var application = await GetTrackedApplicationAsync(applicationId, cancellationToken);

        EnsureStatus(
            application,
            $"changed to {targetStatus}",
            RentalApplicationStatus.Submitted,
            RentalApplicationStatus.UnderReview);

        var decisionAt = DateTimeOffset.UtcNow;
        application.Status = targetStatus;
        application.LandlordResponse = NormalizeOptionalText(landlordResponse);
        application.UpdatedAt = decisionAt;

        var awaitingHumanReviewWorkflows = await dbContext.ApplicationValidationWorkflows
            .Where(workflow => workflow.ApplicationId == applicationId
                && workflow.Status == ApplicationValidationWorkflowStatus.AwaitingHumanReview)
            .ToListAsync(cancellationToken);

        foreach (var workflow in awaitingHumanReviewWorkflows)
        {
            workflow.Status = ApplicationValidationWorkflowStatus.Completed;
            workflow.UpdatedAt = decisionAt;
        }

        await dbContext.SaveChangesAsync(cancellationToken);

        return MapToResponse(application);
    }

    private async Task EnsureNoActiveApplicationAsync(
        Guid tenantId,
        Guid propertyId,
        Guid? applicationIdToExclude,
        CancellationToken cancellationToken)
    {
        var duplicateExists = await dbContext.RentalApplications.AnyAsync(
            application => application.TenantId == tenantId
                && application.PropertyId == propertyId
                && ActiveStatuses.Contains(application.Status)
                && (!applicationIdToExclude.HasValue || application.Id != applicationIdToExclude.Value),
            cancellationToken);

        if (duplicateExists)
        {
            throw RentalApplicationServiceException.Conflict(
                "This tenant already has an active application for the property.");
        }
    }

    private async Task<RentalApplication> GetTenantApplicationAsync(
        Guid applicationId,
        Guid tenantId,
        CancellationToken cancellationToken)
    {
        var application = await dbContext.RentalApplications.SingleOrDefaultAsync(
            item => item.Id == applicationId && item.TenantId == tenantId,
            cancellationToken);

        return application
            ?? throw RentalApplicationServiceException.NotFound(
                "The rental application was not found for this tenant.");
    }

    private async Task<RentalApplication> GetTrackedApplicationAsync(
        Guid applicationId,
        CancellationToken cancellationToken)
    {
        var application = await dbContext.RentalApplications.SingleOrDefaultAsync(
            item => item.Id == applicationId,
            cancellationToken);

        return application
            ?? throw RentalApplicationServiceException.NotFound(
                $"Rental application '{applicationId}' was not found.");
    }

    private static void ValidateTenantId(Guid tenantId)
    {
        if (tenantId == Guid.Empty)
        {
            throw RentalApplicationServiceException.Validation("A tenant ID is required.");
        }
    }

    private static void ValidateApplicationDetails(
        Guid propertyId,
        DateOnly moveInDate,
        decimal monthlyIncome,
        string occupation,
        int numberOfOccupants)
    {
        if (propertyId == Guid.Empty)
        {
            throw RentalApplicationServiceException.Validation("A property ID is required.");
        }

        if (moveInDate <= DateOnly.FromDateTime(DateTime.UtcNow))
        {
            throw RentalApplicationServiceException.Validation(
                "The move-in date must be in the future.");
        }

        if (monthlyIncome <= 0)
        {
            throw RentalApplicationServiceException.Validation(
                "Monthly income must be greater than zero.");
        }

        if (string.IsNullOrWhiteSpace(occupation))
        {
            throw RentalApplicationServiceException.Validation("Occupation is required.");
        }

        if (numberOfOccupants < 1)
        {
            throw RentalApplicationServiceException.Validation(
                "Number of occupants must be at least one.");
        }
    }

    private static void EnsureStatus(
        RentalApplication application,
        string action,
        params RentalApplicationStatus[] allowedStatuses)
    {
        if (!allowedStatuses.Contains(application.Status))
        {
            throw RentalApplicationServiceException.Conflict(
                $"A {application.Status} application cannot be {action}.");
        }
    }

    private static string? NormalizeOptionalText(string? value)
    {
        return string.IsNullOrWhiteSpace(value) ? null : value.Trim();
    }

    private static RentalApplicationResponseDto MapToResponse(RentalApplication application)
    {
        return new RentalApplicationResponseDto
        {
            Id = application.Id,
            TenantId = application.TenantId,
            PropertyId = application.PropertyId,
            MoveInDate = application.MoveInDate,
            MonthlyIncome = application.MonthlyIncome,
            Occupation = application.Occupation,
            NumberOfOccupants = application.NumberOfOccupants,
            TenantNote = application.TenantNote,
            Status = application.Status,
            LandlordResponse = application.LandlordResponse,
            CreatedAt = application.CreatedAt,
            SubmittedAt = application.SubmittedAt,
            UpdatedAt = application.UpdatedAt
        };
    }
}
