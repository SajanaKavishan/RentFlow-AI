using Microsoft.EntityFrameworkCore;
using RentFlow.Api.Data;
using RentFlow.Api.DTOs.PropertyMatching;
using RentFlow.Api.Models;
using RentFlow.Api.Services.Interfaces;

namespace RentFlow.Api.Services;

public sealed class TenantPropertyPreferenceService(
    ApplicationDbContext dbContext,
    TimeProvider timeProvider) : ITenantPropertyPreferenceService
{
    public async Task<TenantPropertyPreferenceResponse> GetAsync(
        Guid userId,
        CancellationToken cancellationToken = default)
    {
        var preference = await dbContext.TenantPropertyPreferences
            .AsNoTracking()
            .SingleOrDefaultAsync(item => item.UserId == userId, cancellationToken);

        return ToResponse(preference);
    }

    public async Task<TenantPropertyPreferenceResponse?> UpdateAsync(
        Guid userId,
        UpdateTenantPropertyPreferenceRequest request,
        CancellationToken cancellationToken = default)
    {
        if (!await dbContext.Users.AnyAsync(
            user => user.Id == userId && user.Role == UserRole.Tenant,
            cancellationToken))
        {
            return null;
        }

        var preference = await dbContext.TenantPropertyPreferences
            .SingleOrDefaultAsync(item => item.UserId == userId, cancellationToken);

        if (preference is null)
        {
            preference = new TenantPropertyPreference { UserId = userId };
            dbContext.TenantPropertyPreferences.Add(preference);
        }

        preference.PreferredCity = NormalizeOptional(request.PreferredCity);
        preference.MaximumMonthlyRent = request.MaximumMonthlyRent;
        preference.MinimumBedrooms = request.MinimumBedrooms;
        preference.MinimumBathrooms = request.MinimumBathrooms;
        preference.PreferredAmenities = (request.PreferredAmenities ?? [])
            .Select(NormalizeOptional)
            .Where(item => item is not null)
            .Cast<string>()
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();
        preference.UpdatedAt = timeProvider.GetUtcNow();

        await dbContext.SaveChangesAsync(cancellationToken);
        return ToResponse(preference);
    }

    public async Task<bool> DeleteAsync(
        Guid userId,
        CancellationToken cancellationToken = default)
    {
        var preference = await dbContext.TenantPropertyPreferences
            .SingleOrDefaultAsync(item => item.UserId == userId, cancellationToken);

        if (preference is null)
        {
            return false;
        }

        dbContext.TenantPropertyPreferences.Remove(preference);
        await dbContext.SaveChangesAsync(cancellationToken);
        return true;
    }

    private static string? NormalizeOptional(string? value) =>
        string.IsNullOrWhiteSpace(value) ? null : value.Trim();

    private static TenantPropertyPreferenceResponse ToResponse(
        TenantPropertyPreference? preference) => new()
    {
        IsConfigured = preference is not null,
        PreferredCity = preference?.PreferredCity,
        MaximumMonthlyRent = preference?.MaximumMonthlyRent,
        MinimumBedrooms = preference?.MinimumBedrooms,
        MinimumBathrooms = preference?.MinimumBathrooms,
        PreferredAmenities = preference?.PreferredAmenities.ToList() ?? [],
        UpdatedAt = preference?.UpdatedAt
    };
}
