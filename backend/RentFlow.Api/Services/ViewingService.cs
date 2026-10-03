using Microsoft.EntityFrameworkCore;
using RentFlow.Api.Data;
using RentFlow.Api.DTOs.Viewings;
using RentFlow.Api.Models;
using RentFlow.Api.Services.Interfaces;

namespace RentFlow.Api.Services;

/// <summary>
/// Provides Viewing Booking operations.
/// </summary>
public class ViewingService(
    ApplicationDbContext dbContext,
    TimeProvider? timeProvider = null,
    ICurrentUserService? currentUser = null) : IViewingService
{
    private DateTimeOffset Now => (timeProvider ?? TimeProvider.System).GetUtcNow();
    private readonly ViewingAvailabilityService availability = new(dbContext, timeProvider);
    public async Task<ViewingResponseDto> CreateAsync(
        Guid tenantId,
        CreateViewingRequestDto request,
        CancellationToken cancellationToken = default)
    {
        if (tenantId == Guid.Empty)
        {
            throw ViewingServiceException.Validation("A tenant ID is required.");
        }

        if (request.PropertyId == Guid.Empty)
        {
            throw ViewingServiceException.Validation("A property ID is required.");
        }

        var requestedDateTimeUtc = request.RequestedDateTime.ToUniversalTime();
        var now = Now;

        if (requestedDateTimeUtc <= now)
        {
            throw ViewingServiceException.Validation("The requested viewing date and time must be in the future.");
        }

        var tenantMessage = request.TenantMessage?.Trim();
        if (string.IsNullOrWhiteSpace(tenantMessage))
            throw ViewingServiceException.Validation("A note for the landlord is required.");
        if (tenantMessage.Length > 500)
            throw ViewingServiceException.Validation("The tenant note must not exceed 500 characters.");
        await using var transaction = await ViewingPropertyLock.AcquireAsync(dbContext, request.PropertyId, cancellationToken);
        var property = await availability.GetPropertyAsync(request.PropertyId, cancellationToken);
        if (property.LandlordId == Guid.Empty)
            throw ViewingServiceException.NotFound("The property was not found.");
        var local = TimeZoneInfo.ConvertTime(requestedDateTimeUtc, ViewingAvailabilityService.ResolveZone(property.ViewingTimeZoneId));
        var slots = await availability.GetSlotsAsync(request.PropertyId, DateOnly.FromDateTime(local.DateTime), cancellationToken);
        if (!slots.Slots.Any(s => s.IsAvailable && s.RequestedDateTime == requestedDateTimeUtc))
            throw ViewingServiceException.Conflict("That time is no longer available. Please choose another slot.");

        var duplicateExists = await dbContext.ViewingRequests.AnyAsync(
            viewing => viewing.TenantId == tenantId
                && viewing.PropertyId == request.PropertyId
                && viewing.RequestedDateTime == requestedDateTimeUtc,
            cancellationToken);

        if (duplicateExists)
        {
            throw ViewingServiceException.Conflict(
                "A viewing request already exists for this tenant, property, and date and time.");
        }

        var viewing = new ViewingRequest
        {
            TenantId = tenantId,
            PropertyId = request.PropertyId,
            RequestedDateTime = requestedDateTimeUtc,
            DurationMinutes = slots.SlotDurationMinutes,
            TenantMessage = tenantMessage,
            Status = ViewingStatus.Pending,
            CreatedAt = now
        };

        dbContext.ViewingRequests.Add(viewing);
        await NotificationDeliveryPolicy.QueueAsync(
            dbContext,
            NotificationEventFactory.ForViewingCreated(viewing, property.LandlordId),
            cancellationToken);

        await dbContext.SaveChangesAsync(cancellationToken);
        if (transaction is not null)
        {
            await transaction.CommitAsync(cancellationToken);
        }

        return await MapToResponseAsync(viewing, cancellationToken);
    }

    public async Task<ViewingResponseDto?> GetByIdAsync(
        Guid viewingId,
        CancellationToken cancellationToken = default)
    {
        var viewing = await dbContext.ViewingRequests
            .AsNoTracking()
            .SingleOrDefaultAsync(item => item.Id == viewingId, cancellationToken);

        return viewing is null ? null : await MapToResponseAsync(viewing, cancellationToken);
    }

    public async Task<ViewingResponseDto?> GetByIdForTenantAsync(
        Guid viewingId,
        Guid tenantId,
        CancellationToken cancellationToken = default)
    {
        var viewing = await dbContext.ViewingRequests
            .AsNoTracking()
            .SingleOrDefaultAsync(
                item => item.Id == viewingId && item.TenantId == tenantId,
                cancellationToken);

        return viewing is null ? null : await MapToResponseAsync(viewing, cancellationToken);
    }

    public async Task<IReadOnlyList<ViewingResponseDto>> GetByTenantAsync(
        Guid tenantId,
        CancellationToken cancellationToken = default)
    {
        var viewings = await dbContext.ViewingRequests
            .AsNoTracking()
            .Where(viewing => viewing.TenantId == tenantId)
            .OrderByDescending(viewing => viewing.RequestedDateTime)
            .ToListAsync(cancellationToken);

        return await MapListAsync(viewings, cancellationToken);
    }

    public async Task<IReadOnlyList<ViewingResponseDto>> GetByPropertyAsync(
        Guid propertyId,
        CancellationToken cancellationToken = default)
    {
        var viewings = await dbContext.ViewingRequests
            .AsNoTracking()
            .Where(viewing => viewing.PropertyId == propertyId)
            .OrderByDescending(viewing => viewing.RequestedDateTime)
            .ToListAsync(cancellationToken);

        return await MapListAsync(viewings, cancellationToken);
    }

    public async Task<ViewingResponseDto> ApproveAsync(
        Guid viewingId,
        string? landlordResponse = null,
        CancellationToken cancellationToken = default)
    {
        var propertyId = await GetViewingPropertyIdAsync(viewingId, cancellationToken);
        await using var transaction = await ViewingPropertyLock.AcquireAsync(dbContext, propertyId, cancellationToken);
        var viewing = await GetTrackedViewingAsync(viewingId, cancellationToken);
        EnsurePending(viewing, ViewingStatus.Approved);
        if (viewing.RequestedDateTime <= Now)
            throw ViewingServiceException.Conflict("A viewing whose requested time has passed cannot be approved.");
        if (viewing.DurationMinutes is not > 0)
            throw ViewingServiceException.Conflict("The legacy viewing duration must be resolved before approval.");
        if (await availability.HasApprovedOverlapAsync(propertyId, viewing.RequestedDateTime,
                viewing.DurationMinutes, viewing.Id, cancellationToken))
            throw ViewingServiceException.Conflict("Another approved viewing overlaps this request.");
        if (landlordResponse?.Length > 1000)
            throw ViewingServiceException.Validation("The landlord response must not exceed 1000 characters.");

        viewing.Status = ViewingStatus.Approved;
        viewing.LandlordResponse = landlordResponse;
        viewing.UpdatedAt = Now;

        await NotificationDeliveryPolicy.QueueAsync(
            dbContext,
            NotificationEventFactory.ForViewing(viewing, ViewingStatus.Approved),
            cancellationToken);

        await dbContext.SaveChangesAsync(cancellationToken);
        if (transaction is not null)
        {
            await transaction.CommitAsync(cancellationToken);
        }

        return await MapToResponseAsync(viewing, cancellationToken);
    }

    public async Task<ViewingResponseDto> RejectAsync(
        Guid viewingId,
        string landlordResponse,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(landlordResponse))
        {
            throw ViewingServiceException.Validation("A landlord response is required when rejecting a viewing.");
        }

        if (landlordResponse.Length > 1000)
            throw ViewingServiceException.Validation("The landlord response must not exceed 1000 characters.");
        var propertyId = await GetViewingPropertyIdAsync(viewingId, cancellationToken);
        await using var transaction = await ViewingPropertyLock.AcquireAsync(dbContext, propertyId, cancellationToken);

        var viewing = await GetTrackedViewingAsync(viewingId, cancellationToken);
        EnsurePending(viewing, ViewingStatus.Rejected);

        viewing.Status = ViewingStatus.Rejected;
        viewing.LandlordResponse = landlordResponse.Trim();
        viewing.UpdatedAt = Now;

        await NotificationDeliveryPolicy.QueueAsync(
            dbContext,
            NotificationEventFactory.ForViewing(viewing, ViewingStatus.Rejected),
            cancellationToken);

        await dbContext.SaveChangesAsync(cancellationToken);
        if (transaction is not null)
        {
            await transaction.CommitAsync(cancellationToken);
        }

        return await MapToResponseAsync(viewing, cancellationToken);
    }

    public async Task<ViewingResponseDto> CancelAsync(
        Guid viewingId,
        Guid tenantId,
        CancellationToken cancellationToken = default)
    {
        if (tenantId == Guid.Empty)
        {
            throw ViewingServiceException.Validation("A tenant ID is required.");
        }

        var reference = await dbContext.ViewingRequests.AsNoTracking()
            .SingleOrDefaultAsync(v => v.Id == viewingId && v.TenantId == tenantId, cancellationToken);
        if (reference is null)
        {
            throw ViewingServiceException.NotFound("The viewing request was not found for this tenant.");
        }
        await using var transaction = await ViewingPropertyLock.AcquireAsync(dbContext, reference.PropertyId, cancellationToken);
        var viewing = await GetTrackedViewingAsync(viewingId, cancellationToken);

        if (viewing.Status is not (ViewingStatus.Pending or ViewingStatus.Approved))
        {
            throw ViewingServiceException.Conflict(
                $"A {viewing.Status} viewing cannot be cancelled.");
        }

        if (viewing.RequestedDateTime.ToUniversalTime() <= Now)
        {
            throw ViewingServiceException.Conflict(
                "A viewing cannot be cancelled at or after its requested date and time.");
        }

        viewing.Status = ViewingStatus.Cancelled;
        viewing.UpdatedAt = Now;

        await dbContext.SaveChangesAsync(cancellationToken);
        if (transaction is not null) await transaction.CommitAsync(cancellationToken);
        return await MapToResponseAsync(viewing, cancellationToken);
    }

    private async Task<ViewingRequest> GetTrackedViewingAsync(
        Guid viewingId,
        CancellationToken cancellationToken)
    {
        var viewing = await dbContext.ViewingRequests
            .SingleOrDefaultAsync(item => item.Id == viewingId, cancellationToken);
        if (viewing is not null) await dbContext.Entry(viewing).ReloadAsync(cancellationToken);

        return viewing
            ?? throw ViewingServiceException.NotFound($"Viewing request '{viewingId}' was not found.");
    }

    private async Task<Guid> GetViewingPropertyIdAsync(Guid id, CancellationToken ct) =>
        await dbContext.ViewingRequests.AsNoTracking().Where(v => v.Id == id)
            .Select(v => (Guid?)v.PropertyId).SingleOrDefaultAsync(ct)
        ?? throw ViewingServiceException.NotFound("The viewing request was not found.");

    private static void EnsurePending(ViewingRequest viewing, ViewingStatus targetStatus)
    {
        if (viewing.Status != ViewingStatus.Pending)
        {
            throw ViewingServiceException.Conflict(
                $"Only pending viewings may be changed to {targetStatus}.");
        }
    }

    private async Task<ViewingResponseDto> MapToResponseAsync(ViewingRequest viewing, CancellationToken ct)
    {
        var property = await dbContext.Properties.AsNoTracking().Where(p => p.Id == viewing.PropertyId)
            .Select(p => new { p.ViewingTimeZoneId, p.LandlordId }).SingleOrDefaultAsync(ct);
        // Never disclose contact data in lists or to tenants/admins. Recheck ownership
        // here as well as retaining the controller's existing access guards.
        var disclosePhone = viewing.Status == ViewingStatus.Approved
            && currentUser is { IsAuthenticated: true, Role: UserRole.Landlord }
            && currentUser.UserId is Guid landlordId
            && property?.LandlordId == landlordId;
        var tenant = await dbContext.Users.AsNoTracking().Where(u => u.Id == viewing.TenantId)
            .Select(u => new { u.FullName, PhoneNumber = disclosePhone ? u.PhoneNumber : null })
            .SingleOrDefaultAsync(ct);
        return MapToResponse(viewing, property?.ViewingTimeZoneId, new ViewingTenantSummaryDto
        {
            DisplayName = TenantDisplayName(tenant?.FullName),
            PhoneNumber = PhoneNumberValidation.UsablePhoneNumber(tenant?.PhoneNumber)
        });
    }

    private async Task<IReadOnlyList<ViewingResponseDto>> MapListAsync(List<ViewingRequest> viewings, CancellationToken ct)
    {
        var ids = viewings.Select(v => v.PropertyId).Distinct().ToArray();
        var zones = await dbContext.Properties.AsNoTracking().Where(p => ids.Contains(p.Id))
            .ToDictionaryAsync(p => p.Id, p => p.ViewingTimeZoneId, ct);
        var tenantIds = viewings.Select(v => v.TenantId).Distinct().ToArray();
        // Batch only the names needed by these viewings; no user directory or phone lookup.
        var names = await dbContext.Users.AsNoTracking().Where(u => tenantIds.Contains(u.Id))
            .ToDictionaryAsync(u => u.Id, u => u.FullName, ct);
        return viewings.Select(v => MapToResponse(v, zones.GetValueOrDefault(v.PropertyId),
            new ViewingTenantSummaryDto { DisplayName = TenantDisplayName(names.GetValueOrDefault(v.TenantId)) }))
            .ToList();
    }

    private static string TenantDisplayName(string? name) =>
        string.IsNullOrWhiteSpace(name) ? "Tenant" : name.Trim();

    private static ViewingResponseDto MapToResponse(
        ViewingRequest viewing, string? zoneId, ViewingTenantSummaryDto tenant)
    {
        var local = zoneId is null ? (DateTimeOffset?)null : TimeZoneInfo.ConvertTime(viewing.RequestedDateTime,
            ViewingAvailabilityService.ResolveZone(zoneId));
        return new ViewingResponseDto
        {
            Id = viewing.Id,
            TenantId = viewing.TenantId,
            Tenant = tenant,
            PropertyId = viewing.PropertyId,
            RequestedDateTime = viewing.RequestedDateTime,
            DurationMinutes = viewing.DurationMinutes,
            TimeZoneId = zoneId,
            RequestedLocalDate = local?.ToString("yyyy-MM-dd", System.Globalization.CultureInfo.InvariantCulture),
            RequestedDisplayTime = local?.ToString("h:mm tt", System.Globalization.CultureInfo.InvariantCulture),
            Status = viewing.Status,
            TenantMessage = viewing.TenantMessage,
            LandlordResponse = viewing.LandlordResponse,
            CreatedAt = viewing.CreatedAt,
            UpdatedAt = viewing.UpdatedAt
        };
    }
}
