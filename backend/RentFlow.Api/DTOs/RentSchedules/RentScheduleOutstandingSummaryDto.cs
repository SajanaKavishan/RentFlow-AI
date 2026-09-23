namespace RentFlow.Api.DTOs.RentSchedules;

public sealed class RentScheduleOutstandingSummaryDto
{
    public decimal TotalPending { get; set; }

    public decimal TotalOverdue { get; set; }

    public decimal TotalOutstanding { get; set; }

    public IReadOnlyList<RentScheduleItemResponseDto> Items { get; set; } = [];
}
