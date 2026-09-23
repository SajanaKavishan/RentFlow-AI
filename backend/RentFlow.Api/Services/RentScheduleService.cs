using Microsoft.EntityFrameworkCore;
using RentFlow.Api.Data;
using RentFlow.Api.DTOs.RentSchedules;
using RentFlow.Api.Models;
using RentFlow.Api.Services.Interfaces;

namespace RentFlow.Api.Services;

public class RentScheduleService : IRentScheduleService
{
    private readonly ApplicationDbContext _dbContext;
    private readonly IPropertyAccessGuard _propertyAccessGuard;
    private readonly TimeProvider _timeProvider;

    public RentScheduleService(
        ApplicationDbContext dbContext,
        IPropertyAccessGuard propertyAccessGuard,
        TimeProvider timeProvider)
    {
        _dbContext = dbContext;
        _propertyAccessGuard = propertyAccessGuard;
        _timeProvider = timeProvider;
    }

    public async Task<bool> CanAccessLeaseAsync(
        Guid leaseAgreementId,
        Guid? userId,
        UserRole? role,
        CancellationToken cancellationToken = default)
    {
        if (leaseAgreementId == Guid.Empty || userId is null)
        {
            return false;
        }

        var lease = await _dbContext.LeaseAgreements
            .AsNoTracking()
            .Where(item => item.Id == leaseAgreementId)
            .Select(item => new { item.TenantId, item.PropertyId })
            .FirstOrDefaultAsync(cancellationToken);

        if (lease is null)
        {
            return false;
        }

        return role switch
        {
            UserRole.Tenant => lease.TenantId == userId.Value,
            UserRole.Landlord => await _propertyAccessGuard.CanAccessPropertyAsync(
                userId.Value, lease.PropertyId, cancellationToken),
            UserRole.Admin => true,
            _ => false
        };
    }

    public async Task<bool> CanAccessScheduleItemAsync(
        Guid scheduleItemId,
        Guid? userId,
        UserRole? role,
        CancellationToken cancellationToken = default)
    {
        var leaseAgreementId = await _dbContext.RentScheduleItems
            .AsNoTracking()
            .Where(item => item.Id == scheduleItemId)
            .Select(item => (Guid?)item.LeaseAgreementId)
            .FirstOrDefaultAsync(cancellationToken);

        return leaseAgreementId is not null
            && await CanAccessLeaseAsync(
                leaseAgreementId.Value,
                userId,
                role,
                cancellationToken);
    }

    public async Task<IReadOnlyList<RentScheduleItemResponseDto>> GenerateForLeaseAsync(
        Guid leaseAgreementId,
        CancellationToken cancellationToken = default)
    {
        var leaseAgreement = await _dbContext.LeaseAgreements
            .FirstOrDefaultAsync(
                lease => lease.Id == leaseAgreementId,
                cancellationToken);

        if (leaseAgreement is null)
        {
            throw RentScheduleServiceException.NotFound(
                "Lease agreement was not found.");
        }

        if (leaseAgreement.Status != LeaseAgreementStatus.Active)
        {
            throw RentScheduleServiceException.Conflict(
                "Rent schedule can only be generated for an active lease agreement.");
        }

        if (leaseAgreement.MonthlyRent <= 0)
        {
            throw RentScheduleServiceException.Validation(
                "Lease agreement monthly rent must be greater than zero.");
        }

        if (leaseAgreement.EndDate < leaseAgreement.StartDate)
        {
            throw RentScheduleServiceException.Validation(
                "Lease agreement has an invalid date range.");
        }

        var scheduleAlreadyExists = await _dbContext.RentScheduleItems
            .AnyAsync(
                item => item.LeaseAgreementId == leaseAgreementId,
                cancellationToken);

        if (scheduleAlreadyExists)
        {
            throw RentScheduleServiceException.Conflict(
                "A rent schedule already exists for this lease agreement.");
        }

        var scheduleItems = new List<RentScheduleItem>();

        var dueDate = leaseAgreement.StartDate;

        while (dueDate <= leaseAgreement.EndDate)
        {
            scheduleItems.Add(new RentScheduleItem
            {
                LeaseAgreementId = leaseAgreement.Id,
                DueDate = dueDate,
                Amount = leaseAgreement.MonthlyRent,
                Status = RentScheduleStatus.Pending,
                CreatedAt = DateTimeOffset.UtcNow
            });

            dueDate = dueDate.AddMonths(1);
        }

        _dbContext.RentScheduleItems.AddRange(scheduleItems);

        await _dbContext.SaveChangesAsync(cancellationToken);

        return scheduleItems
            .Select(MapToResponseDto)
            .ToList();
    }

    public async Task<IReadOnlyList<RentScheduleItemResponseDto>> GetByLeaseAsync(
        Guid leaseAgreementId,
        CancellationToken cancellationToken = default)
    {
        await RefreshOverdueStatusesAsync(
            _dbContext.RentScheduleItems.Where(item => item.LeaseAgreementId == leaseAgreementId),
            cancellationToken);

        var scheduleItems = await _dbContext.RentScheduleItems
            .AsNoTracking()
            .Where(item => item.LeaseAgreementId == leaseAgreementId)
            .OrderBy(item => item.DueDate)
            .ToListAsync(cancellationToken);

        return scheduleItems
            .Select(MapToResponseDto)
            .ToList();
    }

    public async Task<IReadOnlyList<RentScheduleItemResponseDto>> GetByTenantAsync(
        Guid tenantId,
        CancellationToken cancellationToken = default)
    {
        await RefreshOverdueStatusesAsync(
            _dbContext.RentScheduleItems.Where(item => item.LeaseAgreement.TenantId == tenantId),
            cancellationToken);

        var scheduleItems = await _dbContext.RentScheduleItems
            .AsNoTracking()
            .Where(item => item.LeaseAgreement.TenantId == tenantId)
            .OrderBy(item => item.DueDate)
            .ToListAsync(cancellationToken);

        return scheduleItems
            .Select(MapToResponseDto)
            .ToList();
    }

    public async Task<RentScheduleItemResponseDto?> GetByIdAsync(
        Guid id,
        CancellationToken cancellationToken = default)
    {
        await RefreshOverdueStatusesAsync(
            _dbContext.RentScheduleItems.Where(item => item.Id == id),
            cancellationToken);

        var scheduleItem = await _dbContext.RentScheduleItems
            .AsNoTracking()
            .FirstOrDefaultAsync(
                item => item.Id == id,
                cancellationToken);

        if (scheduleItem is null)
        {
            return null;
        }

        return MapToResponseDto(scheduleItem);
    }

    private async Task RefreshOverdueStatusesAsync(
        IQueryable<RentScheduleItem> scopedItems,
        CancellationToken cancellationToken)
    {
        var utcNow = _timeProvider.GetUtcNow();
        var utcToday = DateOnly.FromDateTime(utcNow.UtcDateTime);
        var pendingPastDueItems = scopedItems
            .Where(item =>
                item.Status == RentScheduleStatus.Pending &&
                item.DueDate < utcToday);

        if (_dbContext.Database.IsRelational())
        {
            await pendingPastDueItems.ExecuteUpdateAsync(
                setters => setters
                    .SetProperty(item => item.Status, RentScheduleStatus.Overdue)
                    .SetProperty(item => item.UpdatedAt, utcNow),
                cancellationToken);
            return;
        }

        var overdueItems = await pendingPastDueItems
            .ToListAsync(cancellationToken);

        foreach (var item in overdueItems)
        {
            item.Status = RentScheduleStatus.Overdue;
            item.UpdatedAt = utcNow;
        }

        if (overdueItems.Count > 0)
        {
            await _dbContext.SaveChangesAsync(cancellationToken);
        }
    }

    private static RentScheduleItemResponseDto MapToResponseDto(
        RentScheduleItem item)
    {
        return new RentScheduleItemResponseDto
        {
            Id = item.Id,
            LeaseAgreementId = item.LeaseAgreementId,
            DueDate = item.DueDate,
            Amount = item.Amount,
            Status = item.Status,
            CreatedAt = item.CreatedAt,
            UpdatedAt = item.UpdatedAt
        };
    }
}
