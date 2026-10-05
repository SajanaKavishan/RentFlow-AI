using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Storage;
using RentFlow.Api.Data;

namespace RentFlow.Api.Services;

/// <summary>All viewing writers lock property first, then reload request/schedule state.</summary>
internal static class ViewingPropertyLock
{
    public static async Task<IDbContextTransaction?> AcquireAsync(
        ApplicationDbContext context, Guid propertyId, CancellationToken cancellationToken)
    {
        if (!context.Database.IsRelational()) return null;
        var transaction = await context.Database.BeginTransactionAsync(cancellationToken);
        try
        {
            await context.Database.ExecuteSqlInterpolatedAsync(
                $"SELECT 1 FROM \"Properties\" WHERE \"Id\" = {propertyId} FOR UPDATE", cancellationToken);
            return transaction;
        }
        catch
        {
            await transaction.DisposeAsync();
            throw;
        }
    }
}
