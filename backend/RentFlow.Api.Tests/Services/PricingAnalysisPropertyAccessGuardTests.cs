using Microsoft.EntityFrameworkCore;
using RentFlow.Api.Data;
using RentFlow.Api.Models;
using RentFlow.Api.Services;
using Xunit;

namespace RentFlow.Api.Tests.Services;

public sealed class PricingAnalysisPropertyAccessGuardTests
{
    [Fact]
    public async Task CanAccessPricingAnalysisWorkflowAsync_RequiresPropertyOwnershipAndExistingWorkflow()
    {
        await using var context = CreateContext();
        var ownerId = Guid.NewGuid();
        var ownedProperty = CreateProperty(ownerId);
        var otherProperty = CreateProperty(Guid.NewGuid());
        var ownedWorkflow = new PricingAnalysisWorkflow { PropertyId = ownedProperty.Id };
        var otherWorkflow = new PricingAnalysisWorkflow { PropertyId = otherProperty.Id };
        context.Properties.AddRange(ownedProperty, otherProperty);
        context.PricingAnalysisWorkflows.AddRange(ownedWorkflow, otherWorkflow);
        await context.SaveChangesAsync();
        var guard = new PropertyAccessGuard(context);

        Assert.True(await guard.CanAccessPricingAnalysisWorkflowAsync(ownerId, ownedWorkflow.Id));
        Assert.False(await guard.CanAccessPricingAnalysisWorkflowAsync(ownerId, otherWorkflow.Id));
        Assert.False(await guard.CanAccessPricingAnalysisWorkflowAsync(ownerId, Guid.NewGuid()));
        Assert.False(await guard.CanAccessPricingAnalysisWorkflowAsync(Guid.Empty, ownedWorkflow.Id));
        Assert.False(await guard.CanAccessPricingAnalysisWorkflowAsync(ownerId, Guid.Empty));
    }

    [Fact]
    public async Task ExistingApplicationValidationWorkflowGuardStillUsesApplicationPropertyOwnership()
    {
        await using var context = CreateContext();
        var ownerId = Guid.NewGuid();
        var property = CreateProperty(ownerId);
        var application = new RentalApplication
        {
            PropertyId = property.Id,
            TenantId = Guid.NewGuid(),
            MoveInDate = DateOnly.FromDateTime(DateTime.UtcNow.AddDays(30)),
            MonthlyIncome = 5000m,
            Occupation = "Engineer",
            NumberOfOccupants = 1,
            Status = RentalApplicationStatus.Submitted
        };
        var workflow = new ApplicationValidationWorkflow
        {
            ApplicationId = application.Id,
            Objective = "Validate application"
        };
        context.Properties.Add(property);
        context.RentalApplications.Add(application);
        context.ApplicationValidationWorkflows.Add(workflow);
        await context.SaveChangesAsync();
        var guard = new PropertyAccessGuard(context);

        Assert.True(await guard.CanAccessWorkflowAsync(ownerId, workflow.Id));
        Assert.False(await guard.CanAccessWorkflowAsync(Guid.NewGuid(), workflow.Id));
    }

    private static Property CreateProperty(Guid landlordId) => new()
    {
        LandlordId = landlordId,
        Title = "Access test property",
        Description = "Access test description",
        Address = "1 Test Road",
        City = "Colombo",
        MonthlyRent = 1200m,
        Bedrooms = 2,
        Bathrooms = 1
    };

    private static ApplicationDbContext CreateContext() => new(new DbContextOptionsBuilder<ApplicationDbContext>()
        .UseInMemoryDatabase($"PricingAnalysisGuard-{Guid.NewGuid()}")
        .Options);
}
