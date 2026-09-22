using Microsoft.EntityFrameworkCore;
using RentFlow.Api.Data;
using RentFlow.Api.DTOs.RentalOffers;
using RentFlow.Api.Models;
using RentFlow.Api.Services.Interfaces;

namespace RentFlow.Api.Services;

public class RentalOfferService : IRentalOfferService
{
    private readonly ApplicationDbContext _dbContext;

    public RentalOfferService(ApplicationDbContext dbContext)
    {
        _dbContext = dbContext;
    }

    public async Task<RentalOfferResponseDto> CreateAsync(
        CreateRentalOfferDto dto,
        CancellationToken cancellationToken = default)
    {
        if (dto.MonthlyRent <= 0)
        {
            throw RentalOfferServiceException.Validation(
                "Monthly rent must be greater than zero.");
        }

        if (dto.SecurityDeposit < 0)
        {
            throw RentalOfferServiceException.Validation(
                "Security deposit cannot be negative.");
        }

        if (dto.ProposedEndDate <= dto.ProposedStartDate)
        {
            throw RentalOfferServiceException.Validation(
                "Proposed end date must be after the proposed start date.");
        }

        if (dto.ExpiresAt <= DateTimeOffset.UtcNow)
        {
            throw RentalOfferServiceException.Validation(
                "Offer expiry date must be in the future.");
        }

        var rentalApplication = await _dbContext.RentalApplications
            .FirstOrDefaultAsync(
                application => application.Id == dto.RentalApplicationId,
                cancellationToken);

        if (rentalApplication is null)
        {
            throw RentalOfferServiceException.NotFound(
                "Rental application was not found.");
        }

        if (rentalApplication.Status != RentalApplicationStatus.Approved)
        {
            throw RentalOfferServiceException.Conflict(
                "A rental offer can only be created for an approved rental application.");
        }

        var hasActiveOffer = await _dbContext.RentalOffers
            .AnyAsync(
                offer =>
                    offer.RentalApplicationId == dto.RentalApplicationId &&
                    offer.Status == RentalOfferStatus.Pending,
                cancellationToken);

        if (hasActiveOffer)
        {
            throw RentalOfferServiceException.Conflict(
                "A pending rental offer already exists for this rental application.");
        }

        var rentalOffer = new RentalOffer
        {
            RentalApplicationId = rentalApplication.Id,
            TenantId = rentalApplication.TenantId,
            PropertyId = rentalApplication.PropertyId,
            MonthlyRent = dto.MonthlyRent,
            SecurityDeposit = dto.SecurityDeposit,
            ProposedStartDate = dto.ProposedStartDate,
            ProposedEndDate = dto.ProposedEndDate,
            ExpiresAt = dto.ExpiresAt,
            LandlordNote = dto.LandlordNote,
            Status = RentalOfferStatus.Pending,
            CreatedAt = DateTimeOffset.UtcNow
        };

        _dbContext.RentalOffers.Add(rentalOffer);

        await _dbContext.SaveChangesAsync(cancellationToken);

        return MapToResponseDto(rentalOffer);
    }

    public async Task<RentalOfferResponseDto?> GetByIdAsync(
        Guid id,
        CancellationToken cancellationToken = default)
    {
        var rentalOffer = await _dbContext.RentalOffers
            .AsNoTracking()
            .FirstOrDefaultAsync(
                offer => offer.Id == id,
                cancellationToken);

        if (rentalOffer is null)
        {
            return null;
        }

        return MapToResponseDto(rentalOffer);
    }

    public async Task<IReadOnlyList<RentalOfferResponseDto>> GetByTenantAsync(
        Guid tenantId,
        CancellationToken cancellationToken = default)
    {
        var rentalOffers = await _dbContext.RentalOffers
            .AsNoTracking()
            .Where(offer => offer.TenantId == tenantId)
            .OrderByDescending(offer => offer.CreatedAt)
            .ToListAsync(cancellationToken);

        return rentalOffers
            .Select(MapToResponseDto)
            .ToList();
    }

    public async Task<RentalOfferResponseDto> AcceptAsync(
        Guid offerId,
        Guid tenantId,
        CancellationToken cancellationToken = default)
    {
        var rentalOffer = await _dbContext.RentalOffers
            .FirstOrDefaultAsync(
                offer => offer.Id == offerId,
                cancellationToken);

        if (rentalOffer is null)
        {
            throw RentalOfferServiceException.NotFound(
                "Rental offer was not found.");
        }

        if (rentalOffer.TenantId != tenantId)
        {
            throw RentalOfferServiceException.Conflict(
                "This rental offer does not belong to the current tenant.");
        }

        if (rentalOffer.Status != RentalOfferStatus.Pending)
        {
            throw RentalOfferServiceException.Conflict(
                "Only pending rental offers can be accepted.");
        }

        if (rentalOffer.ExpiresAt <= DateTimeOffset.UtcNow)
        {
            rentalOffer.Status = RentalOfferStatus.Expired;
            rentalOffer.UpdatedAt = DateTimeOffset.UtcNow;

            await _dbContext.SaveChangesAsync(cancellationToken);

            throw RentalOfferServiceException.Conflict(
                "This rental offer has expired and can no longer be accepted.");
        }

        rentalOffer.Status = RentalOfferStatus.Accepted;
        rentalOffer.UpdatedAt = DateTimeOffset.UtcNow;

        await _dbContext.SaveChangesAsync(cancellationToken);

        return MapToResponseDto(rentalOffer);
    }

    public async Task<RentalOfferResponseDto> RejectAsync(
        Guid offerId,
        Guid tenantId,
        CancellationToken cancellationToken = default)
    {
        var rentalOffer = await _dbContext.RentalOffers
            .FirstOrDefaultAsync(
                offer => offer.Id == offerId,
                cancellationToken);

        if (rentalOffer is null)
        {
            throw RentalOfferServiceException.NotFound(
                "Rental offer was not found.");
        }

        if (rentalOffer.TenantId != tenantId)
        {
            throw RentalOfferServiceException.Conflict(
                "This rental offer does not belong to the current tenant.");
        }

        if (rentalOffer.Status != RentalOfferStatus.Pending)
        {
            throw RentalOfferServiceException.Conflict(
                "Only pending rental offers can be rejected.");
        }

        if (rentalOffer.ExpiresAt <= DateTimeOffset.UtcNow)
        {
            rentalOffer.Status = RentalOfferStatus.Expired;
            rentalOffer.UpdatedAt = DateTimeOffset.UtcNow;

            await _dbContext.SaveChangesAsync(cancellationToken);

            throw RentalOfferServiceException.Conflict(
                "This rental offer has expired and can no longer be rejected.");
        }

        rentalOffer.Status = RentalOfferStatus.Rejected;
        rentalOffer.UpdatedAt = DateTimeOffset.UtcNow;

        await _dbContext.SaveChangesAsync(cancellationToken);

        return MapToResponseDto(rentalOffer);
    }

    public async Task<RentalOfferResponseDto> WithdrawAsync(
        Guid offerId,
        CancellationToken cancellationToken = default)
    {
        var rentalOffer = await _dbContext.RentalOffers
            .FirstOrDefaultAsync(
                offer => offer.Id == offerId,
                cancellationToken);

        if (rentalOffer is null)
        {
            throw RentalOfferServiceException.NotFound(
                "Rental offer was not found.");
        }

        if (rentalOffer.Status != RentalOfferStatus.Pending)
        {
            throw RentalOfferServiceException.Conflict(
                "Only pending rental offers can be withdrawn.");
        }

        rentalOffer.Status = RentalOfferStatus.Withdrawn;
        rentalOffer.UpdatedAt = DateTimeOffset.UtcNow;

        await _dbContext.SaveChangesAsync(cancellationToken);

        return MapToResponseDto(rentalOffer);
    }

    private static RentalOfferResponseDto MapToResponseDto(RentalOffer offer)
    {
        return new RentalOfferResponseDto
        {
            Id = offer.Id,
            RentalApplicationId = offer.RentalApplicationId,
            TenantId = offer.TenantId,
            PropertyId = offer.PropertyId,
            MonthlyRent = offer.MonthlyRent,
            SecurityDeposit = offer.SecurityDeposit,
            ProposedStartDate = offer.ProposedStartDate,
            ProposedEndDate = offer.ProposedEndDate,
            ExpiresAt = offer.ExpiresAt,
            Status = offer.Status,
            LandlordNote = offer.LandlordNote,
            CreatedAt = offer.CreatedAt,
            UpdatedAt = offer.UpdatedAt
        };
    }
}