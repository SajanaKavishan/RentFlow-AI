using System.Globalization;
using Microsoft.EntityFrameworkCore;
using RentFlow.Api.Data;
using RentFlow.Api.DTOs.ViewingReviews;
using RentFlow.Api.Models;

namespace RentFlow.Api.Services;

public sealed class ViewingReviewService(ApplicationDbContext db, TimeProvider clock)
{
    private async Task<ViewingRequest> OwnViewing(Guid tenantId, Guid viewingId, CancellationToken ct) =>
        await db.ViewingRequests.AsNoTracking().SingleOrDefaultAsync(v => v.Id == viewingId && v.TenantId == tenantId, ct)
        ?? throw ViewingServiceException.NotFound("The viewing was not found.");

    public async Task<ViewingReviewDto?> GetOwnAsync(Guid tenantId, Guid viewingId, CancellationToken ct = default)
    {
        await OwnViewing(tenantId, viewingId, ct);
        var review = await db.ViewingReviews.AsNoTracking().SingleOrDefaultAsync(r => r.ViewingId == viewingId && r.TenantId == tenantId, ct);
        return review is null ? null : Map(review);
    }

    public async Task<ViewingReviewDto> SaveAsync(Guid tenantId, Guid viewingId, SaveViewingReviewDto input, CancellationToken ct = default)
    {
        if (input.PropertyRating is not (>= 1 and <= 5) || input.LandlordRating is not (>= 1 and <= 5)
            || input.Comment?.Length > 500)
            throw ViewingServiceException.Validation("Choose both ratings from 1 to 5 and use at most 500 comment characters.");
        await using var transaction = db.Database.IsRelational() ? await db.Database.BeginTransactionAsync(ct) : null;
        // Serialize PUTs by the viewing, including the first insert before a review row exists.
        if (transaction is not null)
            await db.Database.ExecuteSqlInterpolatedAsync($"SELECT 1 FROM \"ViewingRequests\" WHERE \"Id\" = {viewingId} AND \"TenantId\" = {tenantId} FOR UPDATE", ct);
        var viewing = await OwnViewing(tenantId, viewingId, ct);
        if (viewing.Status != ViewingStatus.Completed)
            throw ViewingServiceException.Conflict("Only a completed viewing can be reviewed.");
        var review = await db.ViewingReviews.SingleOrDefaultAsync(r => r.ViewingId == viewingId, ct);
        var now = clock.GetUtcNow();
        if (review is null)
        {
            var property = await db.Properties.AsNoTracking().SingleOrDefaultAsync(p => p.Id == viewing.PropertyId, ct)
                ?? throw ViewingServiceException.NotFound("The viewed property was not found.");
            review = new ViewingReview { ViewingId = viewing.Id, TenantId = tenantId, PropertyId = viewing.PropertyId,
                LandlordId = property.LandlordId, CreatedAt = now };
            db.ViewingReviews.Add(review);
        }
        else
        {
            if (transaction is not null) await db.Entry(review).ReloadAsync(ct);
            if (review.TenantId != tenantId) throw ViewingServiceException.NotFound("The review was not found.");
        }
        review.PropertyRating = input.PropertyRating.Value;
        review.LandlordRating = input.LandlordRating.Value;
        review.Comment = string.IsNullOrWhiteSpace(input.Comment) ? null : input.Comment.Trim();
        review.UpdatedAt = now;
        await db.SaveChangesAsync(ct);
        if (transaction is not null) await transaction.CommitAsync(ct);
        return Map(review);
    }

    public async Task<ViewingReviewSummaryDto> GetPublicAsync(Guid propertyId, bool landlord, CancellationToken ct = default)
    {
        var property = await db.Properties.AsNoTracking()
            .Where(p => p.Id == propertyId && (!landlord || (p.Landlord.IsActive && p.Landlord.Role == UserRole.Landlord)))
            .Select(p => new { p.Id, p.LandlordId }).SingleOrDefaultAsync(ct)
            ?? throw ViewingServiceException.NotFound("The property was not found.");
        var query = db.ViewingReviews.AsNoTracking().Where(r => landlord ? r.LandlordId == property.LandlordId : r.PropertyId == property.Id);
        return await SummarizeAsync(query, landlord, ct);
    }

    public async Task<LandlordViewingReviewSummaryDto> GetLandlordSummaryAsync(Guid landlordId, CancellationToken ct = default)
    {
        var landlord = await SummarizeAsync(db.ViewingReviews.AsNoTracking().Where(r => r.LandlordId == landlordId), true, ct);
        // One projection for all owned properties, with at most five written comments each.
        // No per-property API calls or unbounded review materialization.
        var properties = await db.Properties.AsNoTracking().Where(p => p.LandlordId == landlordId)
            .OrderBy(p => p.Title).ThenBy(p => p.Id)
            .Select(p => new {
                p.Id, p.Title,
                Count = db.ViewingReviews.Count(r => r.PropertyId == p.Id),
                Average = db.ViewingReviews.Where(r => r.PropertyId == p.Id).Average(r => (double?)r.PropertyRating),
                Recent = db.ViewingReviews.Where(r => r.PropertyId == p.Id && r.Comment != null && r.Comment != "")
                    .OrderByDescending(r => r.CreatedAt).ThenByDescending(r => r.Id).Take(5)
                    .Select(r => new { r.PropertyRating, r.Comment, r.CreatedAt }).ToList()
            }).ToListAsync(ct);
        return new(landlord, properties.Select(p => new LandlordPropertyReviewSummaryDto(p.Id, p.Title,
            p.Average is null ? null : Math.Round(p.Average.Value, 1, MidpointRounding.AwayFromZero), p.Count,
            p.Recent.Select(r => new PublicViewingReviewDto(r.PropertyRating, r.Comment!, r.CreatedAt.ToString("yyyy-MM", CultureInfo.InvariantCulture))).ToList())).ToList());
    }

    private static async Task<ViewingReviewSummaryDto> SummarizeAsync(IQueryable<ViewingReview> query, bool landlord, CancellationToken ct)
    {
        var count = await query.CountAsync(ct);
        var average = count == 0 ? (double?)null : await query.AverageAsync(r => (double)(landlord ? r.LandlordRating : r.PropertyRating), ct);
        var recent = await query.Where(r => r.Comment != null && r.Comment != "")
            .OrderByDescending(r => r.CreatedAt).ThenByDescending(r => r.Id).Take(5)
            .Select(r => new { Rating = landlord ? r.LandlordRating : r.PropertyRating, r.Comment, r.CreatedAt }).ToListAsync(ct);
        return new(average is null ? null : Math.Round(average.Value, 1, MidpointRounding.AwayFromZero), count,
            recent.Select(r => new PublicViewingReviewDto(r.Rating, r.Comment!, r.CreatedAt.ToString("yyyy-MM", CultureInfo.InvariantCulture))).ToList());
    }

    private static ViewingReviewDto Map(ViewingReview r) => new(r.Id, r.ViewingId, r.PropertyRating, r.LandlordRating, r.Comment, r.CreatedAt, r.UpdatedAt);
}
