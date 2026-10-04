using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Storage;
using RentFlow.Api.Data;
using RentFlow.Api.DTOs.ViewingFollowUps;
using RentFlow.Api.Models;
using RentFlow.Api.Services.Interfaces;

namespace RentFlow.Api.Services;

public sealed class ViewingFollowUpService(ApplicationDbContext db, TimeProvider clock,
    IRentalApplicationService applications) : IViewingFollowUpService
{
    public static readonly TimeSpan ClaimLeaseDuration = TimeSpan.FromMinutes(10);

    // Serialize both claim and response for this authenticated tenant across API instances.
    private async Task<IDbContextTransaction?> LockTenantAsync(Guid tenantId, CancellationToken ct)
    {
        if (tenantId == Guid.Empty) throw RentalApplicationServiceException.Validation("A tenant ID is required.");
        if (!db.Database.IsRelational()) return null;
        var transaction = await db.Database.BeginTransactionAsync(ct);
        try
        {
            await db.Database.ExecuteSqlInterpolatedAsync($"SELECT 1 FROM \"Users\" WHERE \"Id\" = {tenantId} FOR UPDATE", ct);
            return transaction;
        }
        catch { await transaction.DisposeAsync(); throw; }
    }

    public async Task<ViewingFollowUpDto?> ClaimNextAsync(Guid tenantId, CancellationToken cancellationToken = default)
    {
        await using var transaction = await LockTenantAsync(tenantId, cancellationToken);
        var now = clock.GetUtcNow();
        var candidate = await (from viewing in db.ViewingRequests.AsNoTracking()
                               join property in db.Properties.AsNoTracking() on viewing.PropertyId equals property.Id
                               where viewing.TenantId == tenantId && viewing.Status == ViewingStatus.Completed
                                   && viewing.RequestedDateTime.AddMinutes(viewing.DurationMinutes + 60) <= now
                                   && !db.ViewingFollowUps.Any(f => f.ViewingId == viewing.Id
                                       && (f.TenantId != tenantId || f.RespondedAt != null
                                           || (f.ClaimExpiresAt != null && f.ClaimExpiresAt > now)))
                               orderby viewing.RequestedDateTime.AddMinutes(viewing.DurationMinutes + 60), viewing.Id
                               select new { Viewing = viewing, Property = property }).FirstOrDefaultAsync(cancellationToken);
        if (candidate is null) return null;

        var application = await applications.GetEligibilityAsync(tenantId, candidate.Property.Id, cancellationToken);
        var followUp = await db.ViewingFollowUps.SingleOrDefaultAsync(f => f.ViewingId == candidate.Viewing.Id, cancellationToken);
        if (followUp is null)
        {
            followUp = new ViewingFollowUp { ViewingId = candidate.Viewing.Id, TenantId = tenantId };
            db.ViewingFollowUps.Add(followUp);
        }
        else if (db.Database.IsRelational())
        {
            // A context may have tracked this row before another device renewed it.
            await db.Entry(followUp).ReloadAsync(cancellationToken);
        }
        followUp.ClaimedAt = now;
        followUp.ClaimExpiresAt = now + ClaimLeaseDuration;
        await db.SaveChangesAsync(cancellationToken);
        if (transaction is not null) await transaction.CommitAsync(cancellationToken);
        return new ViewingFollowUpDto
        {
            FollowUpId = followUp.Id, ViewingId = followUp.ViewingId, ClaimedAt = now,
            ClaimExpiresAt = followUp.ClaimExpiresAt.Value,
            ViewingCompletedAt = candidate.Viewing.UpdatedAt,
            Property = new() { Id = candidate.Property.Id, Title = candidate.Property.Title,
                Address = candidate.Property.Address, City = candidate.Property.City },
            Application = application
        };
    }

    public async Task<ViewingFollowUpResponseDto> RespondAsync(Guid tenantId, Guid followUpId, ViewingFollowUpDecision decision,
        CancellationToken cancellationToken = default)
    {
        if (!Enum.IsDefined(decision)) throw RentalApplicationServiceException.Validation("Select ApplyNow or NotNow.");
        await using var transaction = await LockTenantAsync(tenantId, cancellationToken);
        var followUp = await db.ViewingFollowUps.SingleOrDefaultAsync(f => f.Id == followUpId && f.TenantId == tenantId
            && db.ViewingRequests.Any(v => v.Id == f.ViewingId && v.TenantId == tenantId), cancellationToken)
            ?? throw RentalApplicationServiceException.NotFound("The viewing follow-up was not found.");
        if (db.Database.IsRelational()) await db.Entry(followUp).ReloadAsync(cancellationToken);
        // A same-decision retry recovers a lost HTTP acknowledgement without rewriting server time.
        if (followUp.Decision.HasValue && followUp.Decision != decision)
            throw RentalApplicationServiceException.Conflict("This viewing follow-up already has a different response.");
        if (!followUp.Decision.HasValue)
        {
            followUp.Decision = decision;
            followUp.RespondedAt = clock.GetUtcNow();
            await db.SaveChangesAsync(cancellationToken);
        }
        if (transaction is not null) await transaction.CommitAsync(cancellationToken);
        return new() { FollowUpId = followUp.Id, Decision = followUp.Decision!.Value.ToString(), RespondedAt = followUp.RespondedAt!.Value };
    }
}
