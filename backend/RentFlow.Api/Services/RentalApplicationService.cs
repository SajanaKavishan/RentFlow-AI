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
    private const string ViewingRequired = "Complete a viewing for this property before starting a rental application.";

    public async Task<IReadOnlyList<PropertyApplicationActionCountDto>> GetActionCountsForLandlordAsync(
        Guid landlordId,
        CancellationToken cancellationToken = default)
    {
        return await (
            from application in dbContext.RentalApplications.AsNoTracking()
            join property in dbContext.Properties.AsNoTracking() on application.PropertyId equals property.Id
            where property.LandlordId == landlordId
                && (application.Status == RentalApplicationStatus.Submitted
                    || application.Status == RentalApplicationStatus.UnderReview)
            group application by application.PropertyId into applications
            select new PropertyApplicationActionCountDto
            {
                PropertyId = applications.Key,
                ActionRequiredCount = applications.Count()
            }).ToListAsync(cancellationToken);
    }

    private IQueryable<ViewingRequest> CompletedViewings(Guid tenantId) =>
        dbContext.ViewingRequests.AsNoTracking().Where(v => v.TenantId == tenantId && v.Status == ViewingStatus.Completed);

    private Task<bool> HasCompletedViewingAsync(Guid tenantId, Guid propertyId, CancellationToken ct) =>
        CompletedViewings(tenantId).AnyAsync(v => v.PropertyId == propertyId, ct);

    private async Task EnsureCompletedViewingAsync(Guid tenantId, Guid propertyId, CancellationToken ct)
    {
        if (!await HasCompletedViewingAsync(tenantId, propertyId, ct))
            throw RentalApplicationServiceException.Conflict(ViewingRequired);
    }

    public async Task<RentalApplicationEligibilityDto> GetEligibilityAsync(Guid tenantId, Guid propertyId,
        CancellationToken cancellationToken = default)
    {
        ValidateTenantId(tenantId);
        var property = await dbContext.Properties.AsNoTracking().SingleOrDefaultAsync(p => p.Id == propertyId, cancellationToken)
            ?? throw RentalApplicationServiceException.NotFound("The property was not found.");
        var completed = await HasCompletedViewingAsync(tenantId, propertyId, cancellationToken);
        var existing = await dbContext.RentalApplications.AsNoTracking()
            .Where(a => a.TenantId == tenantId && a.PropertyId == propertyId && ActiveStatuses.Contains(a.Status))
            .OrderByDescending(a => a.CreatedAt)
            .Select(a => new { a.Id, a.Status }).FirstOrDefaultAsync(cancellationToken);
        return new RentalApplicationEligibilityDto
        {
            CanApply = completed && property.IsAvailable && existing is null,
            HasCompletedViewing = completed,
            Reason = existing is not null ? "You already have an active application for this property."
                : !property.IsAvailable ? "This property is currently unavailable."
                : !completed ? "Complete a viewing before applying for this property." : null,
            ExistingApplicationId = existing?.Id,
            ExistingApplicationStatus = existing?.Status
        };
    }

    public async Task<IReadOnlyList<EligibleApplicationPropertyDto>> GetEligiblePropertiesAsync(Guid tenantId,
        CancellationToken cancellationToken = default)
    {
        ValidateTenantId(tenantId);
        // Query properties once: multiple Completed viewings cannot duplicate a property.
        var completedPropertyIds = CompletedViewings(tenantId).Select(v => v.PropertyId);
        return await dbContext.Properties.AsNoTracking()
            .Where(p => p.IsAvailable && completedPropertyIds.Contains(p.Id)
                && !dbContext.RentalApplications.Any(a => a.TenantId == tenantId && a.PropertyId == p.Id && ActiveStatuses.Contains(a.Status)))
            .OrderBy(p => p.Title).ThenBy(p => p.Id)
            .Select(p => new EligibleApplicationPropertyDto
            { Id = p.Id, Title = p.Title, Address = p.Address, City = p.City, MonthlyRent = p.MonthlyRent })
            .ToListAsync(cancellationToken);
    }

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

        await using var transaction = await ViewingPropertyLock.AcquireAsync(dbContext, request.PropertyId, cancellationToken);
        var property = await dbContext.Properties.AsNoTracking().SingleOrDefaultAsync(p => p.Id == request.PropertyId, cancellationToken)
            ?? throw RentalApplicationServiceException.NotFound("The property was not found.");
        if (!property.IsAvailable)
            throw RentalApplicationServiceException.Conflict("This property is currently unavailable.");

        await EnsureNoActiveApplicationAsync(
            tenantId,
            request.PropertyId,
            applicationIdToExclude: null,
            cancellationToken);

        await EnsureCompletedViewingAsync(tenantId, request.PropertyId, cancellationToken);

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
        if (transaction is not null) await transaction.CommitAsync(cancellationToken);

        return await MapToResponseAsync(application, cancellationToken);
    }

    public async Task<RentalApplicationResponseDto?> GetByIdAsync(
        Guid applicationId,
        CancellationToken cancellationToken = default)
    {
        var application = await dbContext.RentalApplications
            .AsNoTracking()
            .SingleOrDefaultAsync(item => item.Id == applicationId, cancellationToken);

        return application is null ? null : await MapToResponseAsync(application, cancellationToken);
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

        return application is null ? null : await MapToResponseAsync(application, cancellationToken);
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

        return await MapListAsync(applications, cancellationToken);
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

        return await MapListAsync(applications, cancellationToken);
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

        return await MapToResponseAsync(application, cancellationToken);
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
        var isResubmission = application.Status == RentalApplicationStatus.ChangesRequested;
        await EnsureCompletedViewingAsync(application.TenantId, application.PropertyId, cancellationToken);
        application.Status = RentalApplicationStatus.Submitted;
        application.SubmittedAt = now;
        application.UpdatedAt = now;

        var landlordId = await GetLandlordIdAsync(
            application.PropertyId,
            cancellationToken);

        await NotificationDeliveryPolicy.QueueAsync(
            dbContext,
            NotificationEventFactory.ForRentalApplicationSubmission(
                application,
                landlordId,
                isResubmission),
            cancellationToken);

        await using var transaction = dbContext.Database.IsRelational()
            ? await dbContext.Database.BeginTransactionAsync(cancellationToken)
            : null;
        await dbContext.SaveChangesAsync(cancellationToken);
        if (transaction is not null)
        {
            await transaction.CommitAsync(cancellationToken);
        }

        return await MapToResponseAsync(application, cancellationToken);
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

        return await MapToResponseAsync(application, cancellationToken);
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

        return await MapToResponseAsync(application, cancellationToken);
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

        await NotificationDeliveryPolicy.QueueAsync(
            dbContext,
            NotificationEventFactory.ForRentalApplication(application, targetStatus),
            cancellationToken);

        await using var transaction = dbContext.Database.IsRelational()
            ? await dbContext.Database.BeginTransactionAsync(cancellationToken)
            : null;
        await dbContext.SaveChangesAsync(cancellationToken);
        if (transaction is not null)
        {
            await transaction.CommitAsync(cancellationToken);
        }

        return await MapToResponseAsync(application, cancellationToken);
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

    private async Task<Guid> GetLandlordIdAsync(
        Guid propertyId,
        CancellationToken cancellationToken)
    {
        var landlordId = await dbContext.Properties
            .Where(property => property.Id == propertyId)
            .Select(property => (Guid?)property.LandlordId)
            .SingleOrDefaultAsync(cancellationToken);

        if (!landlordId.HasValue || landlordId.Value == Guid.Empty)
        {
            throw RentalApplicationServiceException.NotFound(
                $"Property '{propertyId}' was not found.");
        }

        return landlordId.Value;
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

    // Display-only summaries use the existing authorized application scope. No contact data is exposed.
    private async Task<IReadOnlyList<RentalApplicationResponseDto>> MapListAsync(
        List<RentalApplication> applications, CancellationToken ct)
    {
        var propertyIds = applications.Select(a => a.PropertyId).Distinct().ToArray();
        var tenantIds = applications.Select(a => a.TenantId).Distinct().ToArray();
        var titles = await dbContext.Properties.AsNoTracking().Where(p => propertyIds.Contains(p.Id))
            .ToDictionaryAsync(p => p.Id, p => p.Title, ct);
        var names = await dbContext.Users.AsNoTracking().Where(u => tenantIds.Contains(u.Id))
            .ToDictionaryAsync(u => u.Id, u => u.FullName, ct);
        return applications.Select(application => {
            var response = MapToResponse(application);
            response.PropertyTitle = titles.GetValueOrDefault(application.PropertyId);
            response.ApplicantName = NormalizeOptionalText(names.GetValueOrDefault(application.TenantId));
            return response;
        }).ToList();
    }

    private async Task<RentalApplicationResponseDto> MapToResponseAsync(RentalApplication application, CancellationToken ct) =>
        (await MapListAsync([application], ct))[0];

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
