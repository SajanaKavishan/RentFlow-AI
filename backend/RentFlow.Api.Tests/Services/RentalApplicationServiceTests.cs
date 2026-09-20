using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;
using RentFlow.Api.Data;
using RentFlow.Api.DTOs.RentalApplications;
using RentFlow.Api.Models;
using RentFlow.Api.Services;
using Xunit;

namespace RentFlow.Api.Tests.Services;

public class RentalApplicationServiceTests
{
    [Fact]
    public async Task CreateAsync_CreatesDraftApplication_WhenRequestIsValid()
    {
        await using var context = CreateContext();
        var service = new RentalApplicationService(context);
        var tenantId = Guid.NewGuid();
        var request = CreateValidRequest();

        var result = await service.CreateAsync(tenantId, request);

        Assert.NotEqual(Guid.Empty, result.Id);
        Assert.Equal(tenantId, result.TenantId);
        Assert.Equal(request.PropertyId, result.PropertyId);
        Assert.Equal(request.MoveInDate, result.MoveInDate);
        Assert.Equal(request.MonthlyIncome, result.MonthlyIncome);
        Assert.Equal(request.Occupation, result.Occupation);
        Assert.Equal(request.NumberOfOccupants, result.NumberOfOccupants);
        Assert.Equal(request.TenantNote, result.TenantNote);
        Assert.Equal(RentalApplicationStatus.Draft, result.Status);
        Assert.Equal(TimeSpan.Zero, result.CreatedAt.Offset);
        Assert.Null(result.SubmittedAt);
        Assert.Null(result.UpdatedAt);

        var stored = await context.RentalApplications.SingleAsync();
        Assert.Equal(result.Id, stored.Id);
        Assert.Equal(RentalApplicationStatus.Draft, stored.Status);
    }

    [Fact]
    public async Task CreateAsync_RejectsPastMoveInDate()
    {
        await using var context = CreateContext();
        var service = new RentalApplicationService(context);
        var request = CreateValidRequest();
        request.MoveInDate = UtcToday().AddDays(-1);

        var exception = await Assert.ThrowsAsync<RentalApplicationServiceException>(() =>
            service.CreateAsync(Guid.NewGuid(), request));

        Assert.Equal(RentalApplicationServiceError.Validation, exception.Error);
        Assert.Empty(context.RentalApplications);
    }

    [Theory]
    [InlineData(0)]
    [InlineData(-1)]
    public async Task CreateAsync_RejectsNonPositiveMonthlyIncome(decimal monthlyIncome)
    {
        await using var context = CreateContext();
        var service = new RentalApplicationService(context);
        var request = CreateValidRequest();
        request.MonthlyIncome = monthlyIncome;

        var exception = await Assert.ThrowsAsync<RentalApplicationServiceException>(() =>
            service.CreateAsync(Guid.NewGuid(), request));

        Assert.Equal(RentalApplicationServiceError.Validation, exception.Error);
        Assert.Empty(context.RentalApplications);
    }

    [Fact]
    public async Task CreateAsync_RejectsBlankOccupation()
    {
        await using var context = CreateContext();
        var service = new RentalApplicationService(context);
        var request = CreateValidRequest();
        request.Occupation = "   ";

        var exception = await Assert.ThrowsAsync<RentalApplicationServiceException>(() =>
            service.CreateAsync(Guid.NewGuid(), request));

        Assert.Equal(RentalApplicationServiceError.Validation, exception.Error);
        Assert.Empty(context.RentalApplications);
    }

    [Fact]
    public async Task CreateAsync_RejectsNumberOfOccupantsLessThanOne()
    {
        await using var context = CreateContext();
        var service = new RentalApplicationService(context);
        var request = CreateValidRequest();
        request.NumberOfOccupants = 0;

        var exception = await Assert.ThrowsAsync<RentalApplicationServiceException>(() =>
            service.CreateAsync(Guid.NewGuid(), request));

        Assert.Equal(RentalApplicationServiceError.Validation, exception.Error);
        Assert.Empty(context.RentalApplications);
    }

    [Fact]
    public async Task CreateAsync_RejectsDuplicateActiveApplicationForTenantAndProperty()
    {
        await using var context = CreateContext();
        var tenantId = Guid.NewGuid();
        var propertyId = Guid.NewGuid();
        AddApplication(
            context,
            tenantId: tenantId,
            propertyId: propertyId,
            status: RentalApplicationStatus.UnderReview);
        await context.SaveChangesAsync();
        var service = new RentalApplicationService(context);
        var request = CreateValidRequest(propertyId);

        var exception = await Assert.ThrowsAsync<RentalApplicationServiceException>(() =>
            service.CreateAsync(tenantId, request));

        Assert.Equal(RentalApplicationServiceError.Conflict, exception.Error);
        Assert.Equal(1, await context.RentalApplications.CountAsync());
    }

    [Fact]
    public async Task UpdateAsync_AllowsEditingDraftApplication()
    {
        await using var context = CreateContext();
        var tenantId = Guid.NewGuid();
        var application = AddApplication(context, tenantId: tenantId);
        await context.SaveChangesAsync();
        var service = new RentalApplicationService(context);
        var request = new UpdateRentalApplicationDto
        {
            MoveInDate = UtcToday().AddDays(60),
            MonthlyIncome = 8250m,
            Occupation = "  Architect  ",
            NumberOfOccupants = 3,
            TenantNote = "  Updated note.  "
        };

        var result = await service.UpdateAsync(application.Id, tenantId, request);

        Assert.Equal(request.MoveInDate, result.MoveInDate);
        Assert.Equal(request.MonthlyIncome, result.MonthlyIncome);
        Assert.Equal("Architect", result.Occupation);
        Assert.Equal(request.NumberOfOccupants, result.NumberOfOccupants);
        Assert.Equal("Updated note.", result.TenantNote);
        Assert.Equal(RentalApplicationStatus.Draft, result.Status);
        Assert.NotNull(result.UpdatedAt);
        Assert.Equal(TimeSpan.Zero, result.UpdatedAt!.Value.Offset);
    }

    [Fact]
    public async Task UpdateAsync_RejectsEditingApprovedApplication()
    {
        await using var context = CreateContext();
        var tenantId = Guid.NewGuid();
        var application = AddApplication(
            context,
            tenantId: tenantId,
            status: RentalApplicationStatus.Approved);
        await context.SaveChangesAsync();
        var service = new RentalApplicationService(context);

        var exception = await Assert.ThrowsAsync<RentalApplicationServiceException>(() =>
            service.UpdateAsync(application.Id, tenantId, CreateValidUpdateRequest()));

        Assert.Equal(RentalApplicationServiceError.Conflict, exception.Error);
        Assert.Equal(RentalApplicationStatus.Approved, application.Status);
        Assert.Null(application.UpdatedAt);
    }

    [Fact]
    public async Task SubmitAsync_ChangesDraftToSubmittedAndSetsSubmittedAt()
    {
        await using var context = CreateContext();
        var tenantId = Guid.NewGuid();
        var application = AddApplication(context, tenantId: tenantId);
        await context.SaveChangesAsync();
        var service = new RentalApplicationService(context);

        var result = await service.SubmitAsync(application.Id, tenantId);

        Assert.Equal(RentalApplicationStatus.Submitted, result.Status);
        Assert.NotNull(result.SubmittedAt);
        Assert.Equal(result.SubmittedAt, result.UpdatedAt);
        Assert.Equal(TimeSpan.Zero, result.SubmittedAt!.Value.Offset);
    }

    [Fact]
    public async Task MarkUnderReviewAsync_ChangesSubmittedToUnderReview()
    {
        await using var context = CreateContext();
        var application = AddApplication(
            context,
            status: RentalApplicationStatus.Submitted,
            submittedAt: DateTimeOffset.UtcNow.AddMinutes(-5));
        await context.SaveChangesAsync();
        var service = new RentalApplicationService(context);

        var result = await service.MarkUnderReviewAsync(application.Id);

        Assert.Equal(RentalApplicationStatus.UnderReview, result.Status);
        Assert.NotNull(result.UpdatedAt);
    }

    [Theory]
    [InlineData(RentalApplicationStatus.Submitted)]
    [InlineData(RentalApplicationStatus.UnderReview)]
    public async Task ApproveAsync_ChangesEligibleApplicationToApproved(
        RentalApplicationStatus initialStatus)
    {
        await using var context = CreateContext();
        var application = AddApplication(context, status: initialStatus);
        var workflow = AddValidationWorkflow(context, application.Id);
        var failedWorkflow = AddValidationWorkflow(
            context,
            application.Id,
            ApplicationValidationWorkflowStatus.Failed);
        var workflowCreatedAt = workflow.CreatedAt;
        var workflowUpdatedAt = workflow.UpdatedAt;
        var failedWorkflowUpdatedAt = failedWorkflow.UpdatedAt;
        await context.SaveChangesAsync();
        var service = new RentalApplicationService(context);

        var result = await service.ApproveAsync(application.Id, "  Approved.  ");

        Assert.Equal(RentalApplicationStatus.Approved, result.Status);
        Assert.Equal("Approved.", result.LandlordResponse);
        Assert.NotNull(result.UpdatedAt);
        Assert.Equal(ApplicationValidationWorkflowStatus.Completed, workflow.Status);
        Assert.Equal(workflowCreatedAt, workflow.CreatedAt);
        Assert.True(workflow.UpdatedAt > workflowUpdatedAt);
        Assert.Equal(result.UpdatedAt, workflow.UpdatedAt);
        Assert.True(workflow.RequiresHumanApproval);
        Assert.Equal(ApplicationValidationWorkflowStatus.Failed, failedWorkflow.Status);
        Assert.Equal(failedWorkflowUpdatedAt, failedWorkflow.UpdatedAt);
    }

    [Fact]
    public async Task RejectAsync_CompletesAwaitingHumanReviewWorkflow()
    {
        await using var context = CreateContext();
        var application = AddApplication(context, status: RentalApplicationStatus.UnderReview);
        var workflow = AddValidationWorkflow(context, application.Id);
        var originalCreatedAt = workflow.CreatedAt;
        var originalUpdatedAt = workflow.UpdatedAt;
        await context.SaveChangesAsync();
        var service = new RentalApplicationService(context);

        var result = await service.RejectAsync(application.Id, "  Income could not be verified.  ");

        Assert.Equal(RentalApplicationStatus.Rejected, result.Status);
        Assert.Equal("Income could not be verified.", result.LandlordResponse);
        Assert.Equal(ApplicationValidationWorkflowStatus.Completed, workflow.Status);
        Assert.Equal(originalCreatedAt, workflow.CreatedAt);
        Assert.True(workflow.UpdatedAt > originalUpdatedAt);
        Assert.Equal(result.UpdatedAt, workflow.UpdatedAt);
        Assert.True(workflow.RequiresHumanApproval);
    }

    [Fact]
    public async Task RejectAsync_RequiresNonEmptyLandlordReason()
    {
        await using var context = CreateContext();
        var application = AddApplication(context, status: RentalApplicationStatus.Submitted);
        await context.SaveChangesAsync();
        var service = new RentalApplicationService(context);

        var exception = await Assert.ThrowsAsync<RentalApplicationServiceException>(() =>
            service.RejectAsync(application.Id, "   "));

        Assert.Equal(RentalApplicationServiceError.Validation, exception.Error);
        Assert.Equal(RentalApplicationStatus.Submitted, application.Status);
        Assert.Null(application.UpdatedAt);
    }

    [Theory]
    [InlineData(RentalApplicationStatus.Submitted)]
    [InlineData(RentalApplicationStatus.UnderReview)]
    public async Task RequestChangesAsync_ChangesEligibleApplicationToChangesRequested(
        RentalApplicationStatus initialStatus)
    {
        await using var context = CreateContext();
        var application = AddApplication(context, status: initialStatus);
        var workflow = AddValidationWorkflow(context, application.Id);
        var originalCreatedAt = workflow.CreatedAt;
        var originalUpdatedAt = workflow.UpdatedAt;
        await context.SaveChangesAsync();
        var service = new RentalApplicationService(context);

        var result = await service.RequestChangesAsync(application.Id, "  Add income evidence.  ");

        Assert.Equal(RentalApplicationStatus.ChangesRequested, result.Status);
        Assert.Equal("Add income evidence.", result.LandlordResponse);
        Assert.NotNull(result.UpdatedAt);
        Assert.Equal(ApplicationValidationWorkflowStatus.Completed, workflow.Status);
        Assert.Equal(originalCreatedAt, workflow.CreatedAt);
        Assert.True(workflow.UpdatedAt > originalUpdatedAt);
        Assert.Equal(result.UpdatedAt, workflow.UpdatedAt);
        Assert.True(workflow.RequiresHumanApproval);
    }

    [Fact]
    public async Task LandlordDecision_DoesNotPersistWorkflowCompletion_WhenSaveFails()
    {
        var saveInterceptor = new FailingSaveChangesInterceptor();
        await using var context = CreateContext(saveInterceptor);
        var application = AddApplication(context, status: RentalApplicationStatus.UnderReview);
        var workflow = AddValidationWorkflow(context, application.Id);
        var originalApplicationUpdatedAt = application.UpdatedAt;
        var originalWorkflowUpdatedAt = workflow.UpdatedAt;
        await context.SaveChangesAsync();
        var service = new RentalApplicationService(context);
        saveInterceptor.ShouldFail = true;

        await Assert.ThrowsAsync<DbUpdateException>(() =>
            service.ApproveAsync(application.Id, "Approved."));

        saveInterceptor.ShouldFail = false;
        context.ChangeTracker.Clear();
        var storedApplication = await context.RentalApplications.SingleAsync();
        var storedWorkflow = await context.ApplicationValidationWorkflows.SingleAsync();
        Assert.Equal(RentalApplicationStatus.UnderReview, storedApplication.Status);
        Assert.Null(storedApplication.LandlordResponse);
        Assert.Equal(originalApplicationUpdatedAt, storedApplication.UpdatedAt);
        Assert.Equal(ApplicationValidationWorkflowStatus.AwaitingHumanReview, storedWorkflow.Status);
        Assert.Equal(originalWorkflowUpdatedAt, storedWorkflow.UpdatedAt);
        Assert.Empty(await context.Notifications.ToListAsync());
    }

    [Fact]
    public async Task WithdrawAsync_AllowsOwnerToWithdrawNonTerminalApplication()
    {
        await using var context = CreateContext();
        var tenantId = Guid.NewGuid();
        var application = AddApplication(
            context,
            tenantId: tenantId,
            status: RentalApplicationStatus.UnderReview);
        await context.SaveChangesAsync();
        var service = new RentalApplicationService(context);

        var result = await service.WithdrawAsync(application.Id, tenantId);

        Assert.Equal(RentalApplicationStatus.Withdrawn, result.Status);
        Assert.NotNull(result.UpdatedAt);
    }

    [Fact]
    public async Task WithdrawAsync_RejectsMismatchedTenant()
    {
        await using var context = CreateContext();
        var application = AddApplication(context, tenantId: Guid.NewGuid());
        await context.SaveChangesAsync();
        var service = new RentalApplicationService(context);

        var exception = await Assert.ThrowsAsync<RentalApplicationServiceException>(() =>
            service.WithdrawAsync(application.Id, Guid.NewGuid()));

        Assert.Equal(RentalApplicationServiceError.NotFound, exception.Error);
        Assert.Equal(RentalApplicationStatus.Draft, application.Status);
        Assert.Null(application.UpdatedAt);
    }

    [Fact]
    public async Task ApprovedApplication_CannotTransitionBackToActiveState()
    {
        await using var context = CreateContext();
        var application = AddApplication(
            context,
            status: RentalApplicationStatus.Approved);
        await context.SaveChangesAsync();
        var service = new RentalApplicationService(context);

        var reviewException = await Assert.ThrowsAsync<RentalApplicationServiceException>(() =>
            service.MarkUnderReviewAsync(application.Id));
        var changesException = await Assert.ThrowsAsync<RentalApplicationServiceException>(() =>
            service.RequestChangesAsync(application.Id, "Please revise."));

        Assert.Equal(RentalApplicationServiceError.Conflict, reviewException.Error);
        Assert.Equal(RentalApplicationServiceError.Conflict, changesException.Error);
        Assert.Equal(RentalApplicationStatus.Approved, application.Status);
    }

    [Fact]
    public async Task GetByTenantAsync_ReturnsOnlyThatTenantsApplications()
    {
        await using var context = CreateContext();
        var tenantId = Guid.NewGuid();
        AddApplication(context, tenantId: tenantId, propertyId: Guid.NewGuid());
        AddApplication(
            context,
            tenantId: tenantId,
            propertyId: Guid.NewGuid(),
            status: RentalApplicationStatus.Rejected);
        AddApplication(context, tenantId: Guid.NewGuid(), propertyId: Guid.NewGuid());
        await context.SaveChangesAsync();
        var service = new RentalApplicationService(context);

        var results = await service.GetByTenantAsync(tenantId);

        Assert.Equal(2, results.Count);
        Assert.All(results, result => Assert.Equal(tenantId, result.TenantId));
    }

    [Fact]
    public async Task GetByPropertyAsync_ReturnsOnlyThatPropertysApplications()
    {
        await using var context = CreateContext();
        var propertyId = Guid.NewGuid();
        AddApplication(context, tenantId: Guid.NewGuid(), propertyId: propertyId);
        AddApplication(
            context,
            tenantId: Guid.NewGuid(),
            propertyId: propertyId,
            status: RentalApplicationStatus.Withdrawn);
        AddApplication(context, tenantId: Guid.NewGuid(), propertyId: Guid.NewGuid());
        await context.SaveChangesAsync();
        var service = new RentalApplicationService(context);

        var results = await service.GetByPropertyAsync(propertyId);

        Assert.Equal(2, results.Count);
        Assert.All(results, result => Assert.Equal(propertyId, result.PropertyId));
    }

    private static ApplicationDbContext CreateContext(
        SaveChangesInterceptor? saveChangesInterceptor = null)
    {
        var optionsBuilder = new DbContextOptionsBuilder<ApplicationDbContext>()
            .UseInMemoryDatabase($"RentalApplicationServiceTests-{Guid.NewGuid()}");

        if (saveChangesInterceptor is not null)
        {
            optionsBuilder.AddInterceptors(saveChangesInterceptor);
        }

        return new ApplicationDbContext(optionsBuilder.Options);
    }

    private static CreateRentalApplicationDto CreateValidRequest(Guid? propertyId = null)
    {
        return new CreateRentalApplicationDto
        {
            PropertyId = propertyId ?? Guid.NewGuid(),
            MoveInDate = UtcToday().AddDays(30),
            MonthlyIncome = 7500m,
            Occupation = "Engineer",
            NumberOfOccupants = 2,
            TenantNote = "Looking forward to moving in."
        };
    }

    private static UpdateRentalApplicationDto CreateValidUpdateRequest()
    {
        return new UpdateRentalApplicationDto
        {
            MoveInDate = UtcToday().AddDays(45),
            MonthlyIncome = 8000m,
            Occupation = "Engineer",
            NumberOfOccupants = 2,
            TenantNote = "Updated note."
        };
    }

    private static RentalApplication AddApplication(
        ApplicationDbContext context,
        Guid? tenantId = null,
        Guid? propertyId = null,
        RentalApplicationStatus status = RentalApplicationStatus.Draft,
        DateTimeOffset? submittedAt = null)
    {
        var application = new RentalApplication
        {
            Id = Guid.NewGuid(),
            TenantId = tenantId ?? Guid.NewGuid(),
            PropertyId = propertyId ?? Guid.NewGuid(),
            MoveInDate = UtcToday().AddDays(30),
            MonthlyIncome = 7500m,
            Occupation = "Engineer",
            NumberOfOccupants = 2,
            Status = status,
            CreatedAt = DateTimeOffset.UtcNow,
            SubmittedAt = submittedAt
        };

        context.RentalApplications.Add(application);
        return application;
    }

    private static ApplicationValidationWorkflow AddValidationWorkflow(
        ApplicationDbContext context,
        Guid applicationId,
        ApplicationValidationWorkflowStatus status =
            ApplicationValidationWorkflowStatus.AwaitingHumanReview)
    {
        var createdAt = DateTimeOffset.UtcNow.AddMinutes(-10);
        var workflow = new ApplicationValidationWorkflow
        {
            Id = Guid.NewGuid(),
            ApplicationId = applicationId,
            Objective = "Validate application for landlord review.",
            Status = status,
            CurrentStep = 4,
            CompletenessScore = 100m,
            Recommendation = "Ready for landlord review",
            RequiresHumanApproval = true,
            CreatedAt = createdAt,
            UpdatedAt = createdAt.AddMinutes(5)
        };

        context.ApplicationValidationWorkflows.Add(workflow);
        return workflow;
    }

    private sealed class FailingSaveChangesInterceptor : SaveChangesInterceptor
    {
        public bool ShouldFail { get; set; }

        public override ValueTask<InterceptionResult<int>> SavingChangesAsync(
            DbContextEventData eventData,
            InterceptionResult<int> result,
            CancellationToken cancellationToken = default)
        {
            if (ShouldFail)
            {
                throw new DbUpdateException("Simulated decision persistence failure.");
            }

            return base.SavingChangesAsync(eventData, result, cancellationToken);
        }
    }

    private static DateOnly UtcToday() => DateOnly.FromDateTime(DateTime.UtcNow);
}
