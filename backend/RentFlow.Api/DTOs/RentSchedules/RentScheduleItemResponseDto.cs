using RentFlow.Api.Models;

namespace RentFlow.Api.DTOs.RentSchedules;

public class RentScheduleItemResponseDto
{
    public Guid Id { get; set; }

    public Guid LeaseAgreementId { get; set; }

    public DateOnly DueDate { get; set; }

    public decimal Amount { get; set; }

    public RentScheduleStatus Status { get; set; }

    public DateTimeOffset CreatedAt { get; set; }

    public DateTimeOffset? UpdatedAt { get; set; }
}