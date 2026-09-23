using RentFlow.Api.DTOs.Maintenance;
using RentFlow.Api.Models;
using RentFlow.Api.Services;
using Xunit;

namespace RentFlow.Api.Tests.Services;

public class MaintenanceCoordinationDeterministicToolsTests
{
    [Fact]
    public async Task MaintenanceRequestDataValidationTool_ValidInput_ReturnsDeterministicSuccess()
    {
        var request = new MaintenanceRequest
        {
            Id = Guid.NewGuid(),
            PropertyId = Guid.NewGuid(),
            TenantId = Guid.NewGuid(),
            Title = "Leaking sink",
            Description = "Water is leaking under the sink.",
            Category = MaintenanceCategory.Plumbing,
            Priority = MaintenancePriority.High
        };

        var result = await new MaintenanceRequestDataValidationTool().ValidateAsync(request);

        Assert.True(result.IsValid);
        Assert.Equal(100m, result.CompletenessScore);
        Assert.Empty(result.MissingFields);
        Assert.Empty(result.Warnings);
    }

    [Fact]
    public async Task MaintenanceRequestDataValidationTool_MissingRequiredValues_ReturnsStructuredWarnings()
    {
        var request = new MaintenanceRequest
        {
            Id = Guid.Empty,
            PropertyId = Guid.Empty,
            TenantId = Guid.NewGuid(),
            Title = " ",
            Description = string.Empty,
            Category = (MaintenanceCategory)999,
            Priority = MaintenancePriority.Normal
        };

        var result = await new MaintenanceRequestDataValidationTool().ValidateAsync(request);

        Assert.False(result.IsValid);
        Assert.Contains(nameof(MaintenanceRequest.Id), result.MissingFields);
        Assert.Contains(nameof(MaintenanceRequest.PropertyId), result.MissingFields);
        Assert.Contains(nameof(MaintenanceRequest.Title), result.MissingFields);
        Assert.Contains(nameof(MaintenanceRequest.Description), result.MissingFields);
        Assert.Contains(nameof(MaintenanceRequest.Category), result.MissingFields);
        Assert.Contains("A valid maintenance category is required.", result.Warnings);
    }

    [Fact]
    public async Task MaintenanceRequestDataValidationTool_NullRequest_ThrowsSafeFailure()
    {
        var tool = new MaintenanceRequestDataValidationTool();

        await Assert.ThrowsAsync<ArgumentNullException>(() => tool.ValidateAsync(null));
    }

    [Fact]
    public async Task MaintenanceCoordinationRuleTool_ValidRequestAndEstimate_ReturnsPassedRules()
    {
        var request = new MaintenanceRequest
        {
            Id = Guid.NewGuid(),
            PropertyId = Guid.NewGuid(),
            TenantId = Guid.NewGuid(),
            Title = "Leaking faucet",
            Description = "There is a leak under the kitchen sink.",
            Category = MaintenanceCategory.Plumbing,
            Priority = MaintenancePriority.High
        };
        var estimate = new RepairEstimate
        {
            Id = Guid.NewGuid(),
            MaintenanceRequestId = request.Id,
            TechnicianId = Guid.NewGuid(),
            TotalCost = 250m,
            LaborCost = 150m,
            PartsCost = 75m,
            AdditionalCost = 25m,
            Status = RepairEstimateStatus.Submitted
        };

        var result = await new MaintenanceCoordinationRuleTool().ValidateAsync(request, estimate);

        Assert.True(result.Passed);
        Assert.Contains(MaintenanceCoordinationRuleTool.RequestExistsRule, result.PassedRules);
        Assert.Contains(MaintenanceCoordinationRuleTool.CategoryProvidedRule, result.PassedRules);
        Assert.Contains(MaintenanceCoordinationRuleTool.PriorityProvidedRule, result.PassedRules);
        Assert.Contains(MaintenanceCoordinationRuleTool.DescriptionPresentRule, result.PassedRules);
        Assert.Contains(MaintenanceCoordinationRuleTool.EstimateReadyForReviewRule, result.PassedRules);
        Assert.Empty(result.FailedRules);
    }

    [Fact]
    public async Task MaintenanceCoordinationRuleTool_MissingEstimate_ProducesWarningButStillDeterministic()
    {
        var request = new MaintenanceRequest
        {
            Id = Guid.NewGuid(),
            PropertyId = Guid.NewGuid(),
            TenantId = Guid.NewGuid(),
            Title = "Heating issue",
            Description = "The heater is not working.",
            Category = MaintenanceCategory.Electrical,
            Priority = MaintenancePriority.High
        };

        var result = await new MaintenanceCoordinationRuleTool().ValidateAsync(request, null);

        Assert.True(result.Passed);
        Assert.Contains("No repair estimate was provided; review will continue with incomplete estimate information.", result.Warnings);
        Assert.DoesNotContain(MaintenanceCoordinationRuleTool.EstimateReadyForReviewRule, result.PassedRules);
    }

    [Fact]
    public async Task MaintenanceCoordinationRuleTool_InvalidInput_UsesSafeFailureBehavior()
    {
        var tool = new MaintenanceCoordinationRuleTool();

        await Assert.ThrowsAsync<ArgumentNullException>(() => tool.ValidateAsync(null));
    }
}
