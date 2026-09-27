using Microsoft.EntityFrameworkCore;
using RentFlow.Api.Data;
using RentFlow.Api.DTOs.LeaseAgreements;
using RentFlow.Api.Models;
using RentFlow.Api.Services.Interfaces;

namespace RentFlow.Api.Services;

public class LeaseAgreementService : ILeaseAgreementService
{
    private readonly ApplicationDbContext _dbContext;

    public LeaseAgreementService(ApplicationDbContext dbContext)
    {
        _dbContext = dbContext;
    }

    public async Task<LeaseAgreementResponseDto> CreateAsync(
        CreateLeaseAgreementDto dto,
        CancellationToken cancellationToken = default)
    {
        var rentalOffer = await _dbContext.RentalOffers
            .FirstOrDefaultAsync(
                offer => offer.Id == dto.RentalOfferId,
                cancellationToken);

        if (rentalOffer is null)
        {
            throw LeaseAgreementServiceException.NotFound(
                "Rental offer was not found.");
        }

        if (rentalOffer.Status != RentalOfferStatus.Accepted)
        {
            throw LeaseAgreementServiceException.Conflict(
                "A lease agreement can only be created from an accepted rental offer.");
        }

        var leaseAlreadyExists = await _dbContext.LeaseAgreements
            .AnyAsync(
                lease => lease.RentalOfferId == dto.RentalOfferId,
                cancellationToken);

        if (leaseAlreadyExists)
        {
            throw LeaseAgreementServiceException.Conflict(
                "A lease agreement already exists for this rental offer.");
        }

        if (rentalOffer.ProposedEndDate <= rentalOffer.ProposedStartDate)
        {
            throw LeaseAgreementServiceException.Validation(
                "The rental offer has an invalid lease period.");
        }

        var propertyExists = await _dbContext.Properties
            .AnyAsync(
                property => property.Id == rentalOffer.PropertyId,
                cancellationToken);

        if (!propertyExists)
        {
            throw LeaseAgreementServiceException.NotFound(
                "Property was not found.");
        }

        var leaseAgreement = new LeaseAgreement
        {
            RentalOfferId = rentalOffer.Id,
            TenantId = rentalOffer.TenantId,
            PropertyId = rentalOffer.PropertyId,
            MonthlyRent = rentalOffer.MonthlyRent,
            SecurityDeposit = rentalOffer.SecurityDeposit,
            StartDate = rentalOffer.ProposedStartDate,
            EndDate = rentalOffer.ProposedEndDate,
            Status = LeaseAgreementStatus.Pending,
            CreatedAt = DateTimeOffset.UtcNow
        };

        _dbContext.LeaseAgreements.Add(leaseAgreement);

        await _dbContext.SaveChangesAsync(cancellationToken);

        return MapToResponseDto(leaseAgreement);
    }

    public async Task<LeaseAgreementResponseDto?> GetByIdAsync(
        Guid id,
        CancellationToken cancellationToken = default)
    {
        var leaseAgreement = await _dbContext.LeaseAgreements
            .AsNoTracking()
            .FirstOrDefaultAsync(
                lease => lease.Id == id,
                cancellationToken);

        if (leaseAgreement is null)
        {
            return null;
        }

        return MapToResponseDto(leaseAgreement);
    }

   public async Task<IReadOnlyList<LeaseAgreementResponseDto>> GetByTenantAsync(
        Guid tenantId,
        CancellationToken cancellationToken = default)
    {
        var leaseAgreements = await _dbContext.LeaseAgreements
            .AsNoTracking()
            .Where(lease => lease.TenantId == tenantId)
            .OrderByDescending(lease => lease.CreatedAt)
            .ToListAsync(cancellationToken);

        return leaseAgreements
            .Select(MapToResponseDto)
            .ToList();
    }

    public async Task<IReadOnlyList<LeaseAgreementResponseDto>> GetByLandlordAsync(
        Guid landlordId,
        CancellationToken cancellationToken = default)
    {
        var leaseAgreements = await _dbContext.LeaseAgreements
            .AsNoTracking()
            .Where(lease => _dbContext.Properties.Any(property =>
                property.Id == lease.PropertyId && property.LandlordId == landlordId))
            .OrderByDescending(lease => lease.CreatedAt)
            .ToListAsync(cancellationToken);

        return leaseAgreements.Select(MapToResponseDto).ToList();
    }

    public async Task<LeaseAgreementResponseDto> ActivateAsync(
        Guid leaseId,
        CancellationToken cancellationToken = default)
    {
        var leaseAgreement = await _dbContext.LeaseAgreements
            .FirstOrDefaultAsync(
                lease => lease.Id == leaseId,
                cancellationToken);

        if (leaseAgreement is null)
        {
            throw LeaseAgreementServiceException.NotFound(
                "Lease agreement was not found.");
        }

        if (leaseAgreement.Status != LeaseAgreementStatus.Pending)
        {
            throw LeaseAgreementServiceException.Conflict(
                "Only pending lease agreements can be activated.");
        }

        leaseAgreement.Status = LeaseAgreementStatus.Active;
        leaseAgreement.UpdatedAt = DateTimeOffset.UtcNow;

        await _dbContext.SaveChangesAsync(cancellationToken);

        return MapToResponseDto(leaseAgreement);
    }

    public async Task<LeaseAgreementResponseDto> TerminateAsync(
        Guid leaseId,
        CancellationToken cancellationToken = default)
    {
        var leaseAgreement = await _dbContext.LeaseAgreements
            .FirstOrDefaultAsync(
                lease => lease.Id == leaseId,
                cancellationToken);

        if (leaseAgreement is null)
        {
            throw LeaseAgreementServiceException.NotFound(
                "Lease agreement was not found.");
        }

        if (leaseAgreement.Status != LeaseAgreementStatus.Active)
        {
            throw LeaseAgreementServiceException.Conflict(
                "Only active lease agreements can be terminated.");
        }

        leaseAgreement.Status = LeaseAgreementStatus.Terminated;
        leaseAgreement.UpdatedAt = DateTimeOffset.UtcNow;

        await _dbContext.SaveChangesAsync(cancellationToken);

        return MapToResponseDto(leaseAgreement);
    }

    public async Task<LeaseAgreementResponseDto> CompleteAsync(
        Guid leaseId,
        CancellationToken cancellationToken = default)
    {
        var leaseAgreement = await _dbContext.LeaseAgreements
            .FirstOrDefaultAsync(
                lease => lease.Id == leaseId,
                cancellationToken);

        if (leaseAgreement is null)
        {
            throw LeaseAgreementServiceException.NotFound(
                "Lease agreement was not found.");
        }

        if (leaseAgreement.Status != LeaseAgreementStatus.Active)
        {
            throw LeaseAgreementServiceException.Conflict(
                "Only active lease agreements can be completed.");
        }

        leaseAgreement.Status = LeaseAgreementStatus.Completed;
        leaseAgreement.UpdatedAt = DateTimeOffset.UtcNow;

        await _dbContext.SaveChangesAsync(cancellationToken);

        return MapToResponseDto(leaseAgreement);
    }

    private static LeaseAgreementResponseDto MapToResponseDto(
        LeaseAgreement lease)
    {
        return new LeaseAgreementResponseDto
        {
            Id = lease.Id,
            RentalOfferId = lease.RentalOfferId,
            TenantId = lease.TenantId,
            PropertyId = lease.PropertyId,
            MonthlyRent = lease.MonthlyRent,
            SecurityDeposit = lease.SecurityDeposit,
            StartDate = lease.StartDate,
            EndDate = lease.EndDate,
            Status = lease.Status,
            CreatedAt = lease.CreatedAt,
            UpdatedAt = lease.UpdatedAt
        };
    }
}
