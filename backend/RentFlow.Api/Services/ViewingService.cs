using Microsoft.EntityFrameworkCore;
using RentFlow.Api.Data;
using RentFlow.Api.DTOs.Viewings;
using RentFlow.Api.Models;
using RentFlow.Api.Services.Interfaces;

namespace RentFlow.Api.Services;

/// <summary>
/// Provides Viewing Booking operations.
/// </summary>
public class ViewingService(ApplicationDbContext dbContext) : IViewingService
{
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
        var now = DateTimeOffset.UtcNow;

        if (requestedDateTimeUtc <= now)
        {
            throw ViewingServiceException.Validation("The requested viewing date and time must be in the future.");
        }

        var landlordId = await dbContext.Properties
            .Where(property => property.Id == request.PropertyId)
            .Select(property => (Guid?)property.LandlordId)
            .SingleOrDefaultAsync(cancellationToken);

        if (!landlordId.HasValue || landlordId.Value == Guid.Empty)
        {
            throw ViewingServiceException.NotFound(
                $"Property '{request.PropertyId}' was not found.");
        }

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
            TenantMessage = request.TenantMessage,
            Status = ViewingStatus.Pending,
            CreatedAt = now
        };

        dbContext.ViewingRequests.Add(viewing);
        await NotificationDeliveryPolicy.QueueAsync(
            dbContext,
            NotificationEventFactory.ForViewingCreated(viewing, landlordId.Value),
            cancellationToken);

        await using var transaction = dbContext.Database.IsRelational()
            ? await dbContext.Database.BeginTransactionAsync(cancellationToken)
            : null;
        await dbContext.SaveChangesAsync(cancellationToken);
        if (transaction is not null)
        {
            await transaction.CommitAsync(cancellationToken);
        }

        return MapToResponse(viewing);
    }

    public async Task<ViewingResponseDto?> GetByIdAsync(
        Guid viewingId,
        CancellationToken cancellationToken = default)
    {
        var viewing = await dbContext.ViewingRequests
            .AsNoTracking()
            .SingleOrDefaultAsync(item => item.Id == viewingId, cancellationToken);

        return viewing is null ? null : MapToResponse(viewing);
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

        return viewing is null ? null : MapToResponse(viewing);
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

        return viewings.Select(MapToResponse).ToList();
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

        return viewings.Select(MapToResponse).ToList();
    }

    public async Task<ViewingResponseDto> ApproveAsync(
        Guid viewingId,
        string? landlordResponse = null,
        CancellationToken cancellationToken = default)
    {
        var viewing = await GetTrackedViewingAsync(viewingId, cancellationToken);
        EnsurePending(viewing, ViewingStatus.Approved);

        viewing.Status = ViewingStatus.Approved;
        viewing.LandlordResponse = landlordResponse;
        viewing.UpdatedAt = DateTimeOffset.UtcNow;

        await NotificationDeliveryPolicy.QueueAsync(
            dbContext,
            NotificationEventFactory.ForViewing(viewing, ViewingStatus.Approved),
            cancellationToken);

        await using var transaction = dbContext.Database.IsRelational()
            ? await dbContext.Database.BeginTransactionAsync(cancellationToken)
            : null;
        await dbContext.SaveChangesAsync(cancellationToken);
        if (transaction is not null)
        {
            await transaction.CommitAsync(cancellationToken);
        }

        return MapToResponse(viewing);
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

        var viewing = await GetTrackedViewingAsync(viewingId, cancellationToken);
        EnsurePending(viewing, ViewingStatus.Rejected);

        viewing.Status = ViewingStatus.Rejected;
        viewing.LandlordResponse = landlordResponse.Trim();
        viewing.UpdatedAt = DateTimeOffset.UtcNow;

        await NotificationDeliveryPolicy.QueueAsync(
            dbContext,
            NotificationEventFactory.ForViewing(viewing, ViewingStatus.Rejected),
            cancellationToken);

        await using var transaction = dbContext.Database.IsRelational()
            ? await dbContext.Database.BeginTransactionAsync(cancellationToken)
            : null;
        await dbContext.SaveChangesAsync(cancellationToken);
        if (transaction is not null)
        {
            await transaction.CommitAsync(cancellationToken);
        }

        return MapToResponse(viewing);
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

        var viewing = await GetTrackedViewingAsync(viewingId, cancellationToken);

        if (viewing.TenantId != tenantId)
        {
            throw ViewingServiceException.NotFound("The viewing request was not found for this tenant.");
        }

        if (viewing.Status is not (ViewingStatus.Pending or ViewingStatus.Approved))
        {
            throw ViewingServiceException.Conflict(
                $"A {viewing.Status} viewing cannot be cancelled.");
        }

        if (viewing.RequestedDateTime.ToUniversalTime() <= DateTimeOffset.UtcNow)
        {
            throw ViewingServiceException.Conflict(
                "A viewing cannot be cancelled at or after its requested date and time.");
        }

        viewing.Status = ViewingStatus.Cancelled;
        viewing.UpdatedAt = DateTimeOffset.UtcNow;

        await dbContext.SaveChangesAsync(cancellationToken);

        return MapToResponse(viewing);
    }

    private async Task<ViewingRequest> GetTrackedViewingAsync(
        Guid viewingId,
        CancellationToken cancellationToken)
    {
        var viewing = await dbContext.ViewingRequests
            .SingleOrDefaultAsync(item => item.Id == viewingId, cancellationToken);

        return viewing
            ?? throw ViewingServiceException.NotFound($"Viewing request '{viewingId}' was not found.");
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
            throw ViewingServiceException.NotFound(
                $"Property '{propertyId}' was not found.");
        }

        return landlordId.Value;
    }

    private static void EnsurePending(ViewingRequest viewing, ViewingStatus targetStatus)
    {
        if (viewing.Status != ViewingStatus.Pending)
        {
            throw ViewingServiceException.Conflict(
                $"Only pending viewings may be changed to {targetStatus}.");
        }
    }

    private static ViewingResponseDto MapToResponse(ViewingRequest viewing)
    {
        return new ViewingResponseDto
        {
            Id = viewing.Id,
            TenantId = viewing.TenantId,
            PropertyId = viewing.PropertyId,
            RequestedDateTime = viewing.RequestedDateTime,
            Status = viewing.Status,
            TenantMessage = viewing.TenantMessage,
            LandlordResponse = viewing.LandlordResponse,
            CreatedAt = viewing.CreatedAt,
            UpdatedAt = viewing.UpdatedAt
        };
    }
}
