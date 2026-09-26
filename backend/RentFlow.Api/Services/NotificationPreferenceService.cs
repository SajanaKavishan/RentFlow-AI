using Microsoft.EntityFrameworkCore;
using RentFlow.Api.Data;
using RentFlow.Api.DTOs.Notifications;
using RentFlow.Api.Models;
using RentFlow.Api.Services.Interfaces;

namespace RentFlow.Api.Services;

public sealed class NotificationPreferenceService(ApplicationDbContext dbContext)
    : INotificationPreferenceService
{
    public async Task<NotificationPreferencesResponseDto> GetAsync(
        Guid userId,
        CancellationToken cancellationToken = default)
    {
        var preference = await dbContext.NotificationPreferences
            .AsNoTracking()
            .SingleOrDefaultAsync(item => item.UserId == userId, cancellationToken);

        return ToResponse(preference);
    }

    public async Task<NotificationPreferencesResponseDto?> UpdateAsync(
        Guid userId,
        UpdateNotificationPreferencesRequestDto request,
        CancellationToken cancellationToken = default)
    {
        if (!await dbContext.Users.AnyAsync(user => user.Id == userId, cancellationToken))
        {
            return null;
        }

        var preference = await dbContext.NotificationPreferences
            .SingleOrDefaultAsync(item => item.UserId == userId, cancellationToken);

        if (preference is null)
        {
            preference = new NotificationPreference { UserId = userId };
            dbContext.NotificationPreferences.Add(preference);
        }

        preference.ViewingUpdatesEnabled = request.ViewingUpdatesEnabled;
        preference.RentalApplicationUpdatesEnabled = request.RentalApplicationUpdatesEnabled;
        await dbContext.SaveChangesAsync(cancellationToken);

        return ToResponse(preference);
    }

    private static NotificationPreferencesResponseDto ToResponse(
        NotificationPreference? preference) => new()
    {
        ViewingUpdatesEnabled = preference?.ViewingUpdatesEnabled ?? true,
        RentalApplicationUpdatesEnabled = preference?.RentalApplicationUpdatesEnabled ?? true,
        AccountSecurityUpdatesEnabled = true
    };
}
