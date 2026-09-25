using System.ComponentModel.DataAnnotations;

namespace RentFlow.Api.Configuration;

public sealed class StaffProvisioningOptions
{
    public const string SectionName = "StaffProvisioning";

    [Range(5, 1440)]
    public int SetupTokenLifetimeMinutes { get; init; } = 60;
}
