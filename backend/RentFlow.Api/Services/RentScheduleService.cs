using Microsoft.EntityFrameworkCore;
using RentFlow.Api.Data;
using RentFlow.Api.DTOs.RentSchedules;
using RentFlow.Api.Models;
using RentFlow.Api.Services.Interfaces;

namespace RentFlow.Api.Services;

public class RentScheduleService : IRentScheduleService
{
    private readonly ApplicationDbContext _dbContext;

    public RentScheduleService(ApplicationDbContext dbContext)
    {
        _dbContext = dbContext;
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