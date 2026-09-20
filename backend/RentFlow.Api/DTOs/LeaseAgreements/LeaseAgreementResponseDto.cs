using RentFlow.Api.Models;

namespace RentFlow.Api.DTOs.LeaseAgreements;

public class LeaseAgreementResponseDto
{
    public Guid Id { get; set; }

    public Guid RentalOfferId { get; set; }

    public Guid TenantId { get; set; }

    public Guid PropertyId { get; set; }

    public decimal MonthlyRent { get; set; }

    public decimal SecurityDeposit { get; set; }

    public DateOnly StartDate { get; set; }

    public DateOnly EndDate { get; set; }

    public LeaseAgreementStatus Status { get; set; }

    public DateTimeOffset CreatedAt { get; set; }

    public DateTimeOffset? UpdatedAt { get; set; }
}