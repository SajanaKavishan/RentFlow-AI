namespace RentFlow.Api.DTOs.Viewings;

/// <summary>Tenant identity scoped to an authorized viewing response.</summary>
public sealed class ViewingTenantSummaryDto
{
    public string DisplayName { get; init; } = "Tenant";

    public string? PhoneNumber { get; init; }
}
