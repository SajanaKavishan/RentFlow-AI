using RentFlow.Api.DTOs.Payments;

namespace RentFlow.Api.Services.Interfaces;

public interface IPaymentService
{
    Task<PaymentResponseDto> CreateAsync(
        CreatePaymentDto dto,
        Guid tenantId,
        CancellationToken cancellationToken = default);

    Task<PaymentResponseDto?> GetByIdAsync(
        Guid id,
        CancellationToken cancellationToken = default);

    Task<IReadOnlyList<PaymentResponseDto>> GetByTenantAsync(
        Guid tenantId,
        CancellationToken cancellationToken = default);

    Task<IReadOnlyList<PaymentResponseDto>> GetByLandlordAsync(
        Guid landlordId,
        CancellationToken cancellationToken = default);

    Task<PaymentResponseDto> CompleteAsync(
        Guid paymentId,
        CancellationToken cancellationToken = default);

    Task<PaymentResponseDto> FailAsync(
        Guid paymentId,
        CancellationToken cancellationToken = default);
}
