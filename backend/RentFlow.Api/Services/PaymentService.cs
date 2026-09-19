using Microsoft.EntityFrameworkCore;
using RentFlow.Api.Data;
using RentFlow.Api.DTOs.Payments;
using RentFlow.Api.Models;
using RentFlow.Api.Services.Interfaces;

namespace RentFlow.Api.Services;

public class PaymentService : IPaymentService
{
    private readonly ApplicationDbContext _dbContext;

    public PaymentService(ApplicationDbContext dbContext)
    {
        _dbContext = dbContext;
    }

    public async Task<PaymentResponseDto> CreateAsync(
        CreatePaymentDto dto,
        Guid tenantId,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(dto.PaymentMethod))
        {
            throw PaymentServiceException.Validation(
                "Payment method is required.");
        }

        var rentScheduleItem = await _dbContext.RentScheduleItems
            .Include(item => item.LeaseAgreement)
            .FirstOrDefaultAsync(
                item => item.Id == dto.RentScheduleItemId,
                cancellationToken);

        if (rentScheduleItem is null)
        {
            throw PaymentServiceException.NotFound(
                "Rent schedule item was not found.");
        }

        if (rentScheduleItem.LeaseAgreement.TenantId != tenantId)
        {
            throw PaymentServiceException.Conflict(
                "This rent schedule item does not belong to the authenticated tenant.");
        }

        if (rentScheduleItem.Status == RentScheduleStatus.Paid)
        {
            throw PaymentServiceException.Conflict(
                "This rent schedule item has already been paid.");
        }

        var completedPaymentExists = await _dbContext.Payments
            .AnyAsync(
                payment =>
                    payment.RentScheduleItemId == rentScheduleItem.Id &&
                    payment.Status == PaymentStatus.Completed,
                cancellationToken);

        if (completedPaymentExists)
        {
            throw PaymentServiceException.Conflict(
                "A completed payment already exists for this rent schedule item.");
        }

        var payment = new Payment
        {
            RentScheduleItemId = rentScheduleItem.Id,
            TenantId = tenantId,
            Amount = rentScheduleItem.Amount,
            PaymentMethod = dto.PaymentMethod.Trim(),
            TransactionReference = string.IsNullOrWhiteSpace(dto.TransactionReference)
                ? null
                : dto.TransactionReference.Trim(),
            Status = PaymentStatus.Pending,
            CreatedAt = DateTimeOffset.UtcNow
        };

        _dbContext.Payments.Add(payment);

        await _dbContext.SaveChangesAsync(cancellationToken);

        return MapToResponseDto(payment);
    }

    public async Task<PaymentResponseDto?> GetByIdAsync(
        Guid id,
        CancellationToken cancellationToken = default)
    {
        var payment = await _dbContext.Payments
            .AsNoTracking()
            .FirstOrDefaultAsync(
                payment => payment.Id == id,
                cancellationToken);

        if (payment is null)
        {
            return null;
        }

        return MapToResponseDto(payment);
    }

    public async Task<IReadOnlyList<PaymentResponseDto>> GetByTenantAsync(
        Guid tenantId,
        CancellationToken cancellationToken = default)
    {
        var payments = await _dbContext.Payments
            .AsNoTracking()
            .Where(payment => payment.TenantId == tenantId)
            .OrderByDescending(payment => payment.CreatedAt)
            .ToListAsync(cancellationToken);

        return payments
            .Select(MapToResponseDto)
            .ToList();
    }

    public async Task<PaymentResponseDto> CompleteAsync(
        Guid paymentId,
        CancellationToken cancellationToken = default)
    {
        var payment = await _dbContext.Payments
            .Include(payment => payment.RentScheduleItem)
            .FirstOrDefaultAsync(
                payment => payment.Id == paymentId,
                cancellationToken);

        if (payment is null)
        {
            throw PaymentServiceException.NotFound(
                "Payment was not found.");
        }

        if (payment.Status != PaymentStatus.Pending)
        {
            throw PaymentServiceException.Conflict(
                "Only pending payments can be completed.");
        }

        payment.Status = PaymentStatus.Completed;
        payment.PaidAt = DateTimeOffset.UtcNow;
        payment.UpdatedAt = DateTimeOffset.UtcNow;

        payment.RentScheduleItem.Status = RentScheduleStatus.Paid;
        payment.RentScheduleItem.UpdatedAt = DateTimeOffset.UtcNow;

        await _dbContext.SaveChangesAsync(cancellationToken);

        return MapToResponseDto(payment);
    }

    public async Task<PaymentResponseDto> FailAsync(
        Guid paymentId,
        CancellationToken cancellationToken = default)
    {
        var payment = await _dbContext.Payments
            .FirstOrDefaultAsync(
                payment => payment.Id == paymentId,
                cancellationToken);

        if (payment is null)
        {
            throw PaymentServiceException.NotFound(
                "Payment was not found.");
        }

        if (payment.Status != PaymentStatus.Pending)
        {
            throw PaymentServiceException.Conflict(
                "Only pending payments can be marked as failed.");
        }

        payment.Status = PaymentStatus.Failed;
        payment.UpdatedAt = DateTimeOffset.UtcNow;

        await _dbContext.SaveChangesAsync(cancellationToken);

        return MapToResponseDto(payment);
    }

    private static PaymentResponseDto MapToResponseDto(
        Payment payment)
    {
        return new PaymentResponseDto
        {
            Id = payment.Id,
            RentScheduleItemId = payment.RentScheduleItemId,
            TenantId = payment.TenantId,
            Amount = payment.Amount,
            PaymentMethod = payment.PaymentMethod,
            TransactionReference = payment.TransactionReference,
            Status = payment.Status,
            PaidAt = payment.PaidAt,
            CreatedAt = payment.CreatedAt,
            UpdatedAt = payment.UpdatedAt
        };
    }
}