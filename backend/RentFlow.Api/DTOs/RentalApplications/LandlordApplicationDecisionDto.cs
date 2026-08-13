using RentFlow.Api.Models;

namespace RentFlow.Api.DTOs.RentalApplications;

/// <summary>
/// Carries a landlord's decision for a rental application.
/// </summary>
public class LandlordApplicationDecisionDto
{
    public RentalApplicationStatus Status { get; set; }

    public string? LandlordResponse { get; set; }
}
