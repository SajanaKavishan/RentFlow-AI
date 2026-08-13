using RentFlow.Api.Models;

namespace RentFlow.Api.DTOs.Viewings;

/// <summary>
/// Carries the input required to update a viewing request's status.
/// </summary>
public class UpdateViewingStatusDto
{
    public ViewingStatus Status { get; set; }

    public string? LandlordResponse { get; set; }
}
