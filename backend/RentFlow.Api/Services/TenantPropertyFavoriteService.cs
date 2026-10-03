using Microsoft.EntityFrameworkCore;
using RentFlow.Api.Data;
using RentFlow.Api.DTOs.PropertyMatching;
using RentFlow.Api.Models;
using RentFlow.Api.Services.Interfaces;

namespace RentFlow.Api.Services;

public sealed class TenantPropertyFavoriteService(
    ApplicationDbContext dbContext,
    TimeProvider timeProvider) : ITenantPropertyFavoriteService
{
    public async Task<TenantPropertyFavoritesResponse> GetAsync(
        Guid tenantId,
        CancellationToken cancellationToken = default)
    {
        var propertyIds = await dbContext.TenantPropertyFavorites
            .AsNoTracking()
            .Where(favorite => favorite.TenantId == tenantId)
            .OrderByDescending(favorite => favorite.CreatedAt)
            .Select(favorite => favorite.PropertyId)
            .ToListAsync(cancellationToken);

        return new TenantPropertyFavoritesResponse { PropertyIds = propertyIds };
    }

    public async Task<bool> AddAsync(
        Guid tenantId,
        Guid propertyId,
        CancellationToken cancellationToken = default)
    {
        var propertyExists = await dbContext.Properties.AnyAsync(
            property => property.Id == propertyId && property.IsAvailable,
            cancellationToken);
        if (!propertyExists)
        {
            return false;
        }

        var alreadyExists = await dbContext.TenantPropertyFavorites.AnyAsync(
            favorite => favorite.TenantId == tenantId && favorite.PropertyId == propertyId,
            cancellationToken);
        if (!alreadyExists)
        {
            dbContext.TenantPropertyFavorites.Add(new TenantPropertyFavorite
            {
                TenantId = tenantId,
                PropertyId = propertyId,
                CreatedAt = timeProvider.GetUtcNow()
            });
            await dbContext.SaveChangesAsync(cancellationToken);
        }

        return true;
    }

    public async Task RemoveAsync(
        Guid tenantId,
        Guid propertyId,
        CancellationToken cancellationToken = default)
    {
        var favorite = await dbContext.TenantPropertyFavorites.SingleOrDefaultAsync(
            item => item.TenantId == tenantId && item.PropertyId == propertyId,
            cancellationToken);
        if (favorite is null)
        {
            return;
        }

        dbContext.TenantPropertyFavorites.Remove(favorite);
        await dbContext.SaveChangesAsync(cancellationToken);
    }
}
