using RentFlow.Api.Models;

namespace RentFlow.Api.DTOs.RentalApplications;

public sealed class RentalApplicationEligibilityDto
{
    public bool CanApply { get; set; }
    public bool HasCompletedViewing { get; set; }
    public string? Reason { get; set; }
    public Guid? ExistingApplicationId { get; set; }
    public RentalApplicationStatus? ExistingApplicationStatus { get; set; }
}

public sealed class EligibleApplicationPropertyDto
{
    public Guid Id { get; set; }
    public string Title { get; set; } = string.Empty;
    public string Address { get; set; } = string.Empty;
    public string City { get; set; } = string.Empty;
    public decimal MonthlyRent { get; set; }
}
