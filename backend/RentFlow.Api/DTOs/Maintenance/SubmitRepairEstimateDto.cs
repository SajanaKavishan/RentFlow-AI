namespace RentFlow.Api.DTOs.Maintenance;

/// <summary>
/// Carries technician-provided repair cost inputs.
/// </summary>
public class SubmitRepairEstimateDto
{
    public decimal LaborCost { get; set; }

    public decimal PartsCost { get; set; }

    public decimal AdditionalCost { get; set; }

    public string? Notes { get; set; }
}
