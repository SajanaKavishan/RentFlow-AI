using Microsoft.EntityFrameworkCore;
using RentFlow.Api.Data;
using RentFlow.Api.DTOs.Maintenance;
using RentFlow.Api.Models;
using RentFlow.Api.Services;
using Xunit;

namespace RentFlow.Api.Tests.Services;

public class MaintenanceRequestServiceTests
{
    [Fact]
    public async Task CreateAsync_CreatesSubmittedRequest_WhenRequestIsValid()
    {
        await using var context = CreateContext();
        var service = new MaintenanceRequestService(context);
        var tenantId = Guid.NewGuid();
        var request = CreateValidRequest();

        await MaintenanceTenancyFixture.SeedAsync(context, tenantId, request.PropertyId);
        var result = await service.CreateAsync(tenantId, request);

        Assert.NotEqual(Guid.Empty, result.Id);
        Assert.Equal(tenantId, result.TenantId);
        Assert.Equal(request.PropertyId, result.PropertyId);
        Assert.Equal("Leaking kitchen tap", result.Title);
        Assert.Equal(MaintenanceRequestStatus.Submitted, result.Status);
        Assert.Equal(TimeSpan.Zero, result.CreatedAt.Offset);
        Assert.Null(result.UpdatedAt);
        Assert.Equal(result.Id, (await context.MaintenanceRequests.SingleAsync()).Id);
        var notice = Assert.Single(await context.Notifications.Where(n => n.EventType == NotificationEventTypes.MaintenanceSubmitted).ToListAsync());
        Assert.Equal((await context.Properties.SingleAsync(p => p.Id == request.PropertyId)).LandlordId, notice.RecipientId);
        Assert.Equal(result.Id, notice.RelatedResourceId);
        Assert.DoesNotContain(result.Id.ToString(), notice.Message);
    }

    [Fact]
    public async Task GetTechnicianChoicesAsync_ReturnsOnlyActiveTechniciansWithNames()
    {
        await using var context = CreateContext();
        var activeTechnicianId = Guid.NewGuid();
        context.Users.AddRange(
            CreateUser(activeTechnicianId, UserRole.MaintenanceTechnician, true, "Active Tech"),
            CreateUser(Guid.NewGuid(), UserRole.MaintenanceTechnician, false, "Inactive Tech"),
            CreateUser(Guid.NewGuid(), UserRole.Tenant, true, "Tenant"));
        await context.SaveChangesAsync();

        var choices = await new MaintenanceRequestService(context)
            .GetTechnicianChoicesAsync();

        var choice = Assert.Single(choices);
        Assert.Equal(activeTechnicianId, choice.Id);
        Assert.Equal("Active Tech", choice.Name);
    }

    [Fact]
    public async Task GetByIdAsync_ProjectsTenantAndTechnicianDisplayNames()
    {
        await using var context = CreateContext();
        var tenantId = Guid.NewGuid();
        var technicianId = Guid.NewGuid();
        var request = AddRequest(context, tenantId: tenantId, technicianId: technicianId);
        context.Users.AddRange(
            CreateUser(tenantId, UserRole.Tenant, true, "Chamodya Sayanjali"),
            CreateUser(technicianId, UserRole.MaintenanceTechnician, true, "Morgan Technician"));
        await context.SaveChangesAsync();

        var result = await new MaintenanceRequestService(context).GetByIdAsync(request.Id);

        Assert.Equal("Chamodya Sayanjali", result!.TenantName);
        Assert.Equal("Morgan Technician", result.AssignedTechnicianName);
    }

    [Fact]
    public async Task CreateAsync_RejectsEmptyPropertyId()
    {
        await using var context = CreateContext();
        var request = CreateValidRequest();
        request.PropertyId = Guid.Empty;

        var exception = await Assert.ThrowsAsync<MaintenanceRequestServiceException>(() =>
            new MaintenanceRequestService(context).CreateAsync(Guid.NewGuid(), request));

        Assert.Equal(MaintenanceRequestServiceError.Validation, exception.Error);
        Assert.Empty(context.MaintenanceRequests);
    }

    [Fact]
    public async Task CreateAsync_RejectsEmptyTenantId()
    {
        await using var context = CreateContext();

        var exception = await Assert.ThrowsAsync<MaintenanceRequestServiceException>(() =>
            new MaintenanceRequestService(context).CreateAsync(Guid.Empty, CreateValidRequest()));

        Assert.Equal(MaintenanceRequestServiceError.Validation, exception.Error);
    }

    [Fact]
    public async Task CreateAsync_DerivesBlankTitleFromDescription()
    {
        await using var context = CreateContext();
        var request = CreateValidRequest();
        request.Title = "   ";
        var tenantId = Guid.NewGuid();
        await MaintenanceTenancyFixture.SeedAsync(context, tenantId, request.PropertyId);
        var result = await new MaintenanceRequestService(context).CreateAsync(tenantId, request);
        Assert.Equal("Water is leaking from the kitchen tap whenever it is used", result.Title);
    }

    [Fact]
    public async Task CreateAsync_RejectsTitleLongerThan200Characters()
    {
        await using var context = CreateContext();
        var request = CreateValidRequest();
        request.Title = new string('A', 201);

        var exception = await Assert.ThrowsAsync<MaintenanceRequestServiceException>(() =>
            new MaintenanceRequestService(context).CreateAsync(Guid.NewGuid(), request));

        Assert.Equal(MaintenanceRequestServiceError.Validation, exception.Error);
    }

    [Fact]
    public async Task CreateAsync_RejectsDescriptionLongerThan4000Characters()
    {
        await using var context = CreateContext();
        var request = CreateValidRequest();
        request.Description = new string('A', 4001);

        var exception = await Assert.ThrowsAsync<MaintenanceRequestServiceException>(() =>
            new MaintenanceRequestService(context).CreateAsync(Guid.NewGuid(), request));

        Assert.Equal(MaintenanceRequestServiceError.Validation, exception.Error);
    }

    [Fact]
    public async Task UpdateTenantRequestAsync_AllowsTenantToUpdateOwnSubmittedRequest()
    {
        await using var context = CreateContext();
        var tenantId = Guid.NewGuid();
        var maintenanceRequest = AddRequest(context, tenantId: tenantId);
        await context.SaveChangesAsync();
        var update = new UpdateMaintenanceRequestDto
        {
            Title = "  Water leak under the sink  ",
            Description = "  The leak has become more frequent.  ",
            Category = MaintenanceCategory.Plumbing,
            Priority = MaintenancePriority.High,
            TenantAccessNotes = "  Call before visiting.  "
        };

        var result = await new MaintenanceRequestService(context)
            .UpdateTenantRequestAsync(maintenanceRequest.Id, tenantId, update);

        Assert.Equal("Water leak under the sink", result.Title);
        Assert.Equal("The leak has become more frequent.", result.Description);
        Assert.Equal(MaintenancePriority.High, result.Priority);
        Assert.Equal("Call before visiting.", result.TenantAccessNotes);
        Assert.NotNull(result.UpdatedAt);
    }

    [Fact]
    public async Task UpdateTenantRequestAsync_RejectsAnotherTenantsRequest()
    {
        await using var context = CreateContext();
        var maintenanceRequest = AddRequest(context, tenantId: Guid.NewGuid());
        await context.SaveChangesAsync();

        var exception = await Assert.ThrowsAsync<MaintenanceRequestServiceException>(() =>
            new MaintenanceRequestService(context).UpdateTenantRequestAsync(
                maintenanceRequest.Id,
                Guid.NewGuid(),
                CreateValidUpdate()));

        Assert.Equal(MaintenanceRequestServiceError.NotFound, exception.Error);
    }

    [Theory]
    [InlineData(MaintenanceRequestStatus.Triaged)]
    [InlineData(MaintenanceRequestStatus.Completed)]
    [InlineData(MaintenanceRequestStatus.Cancelled)]
    public async Task UpdateTenantRequestAsync_RejectsNonSubmittedRequest(
        MaintenanceRequestStatus status)
    {
        await using var context = CreateContext();
        var tenantId = Guid.NewGuid();
        var maintenanceRequest = AddRequest(context, tenantId: tenantId, status: status);
        await context.SaveChangesAsync();

        var exception = await Assert.ThrowsAsync<MaintenanceRequestServiceException>(() =>
            new MaintenanceRequestService(context).UpdateTenantRequestAsync(
                maintenanceRequest.Id,
                tenantId,
                CreateValidUpdate()));

        Assert.Equal(MaintenanceRequestServiceError.Conflict, exception.Error);
    }

    [Fact]
    public async Task TriageAsync_ChangesSubmittedRequestToTriaged()
    {
        await using var context = CreateContext();
        var maintenanceRequest = AddRequest(context);
        await context.SaveChangesAsync();

        var result = await new MaintenanceRequestService(context).TriageAsync(
            maintenanceRequest.Id,
            new TriageMaintenanceRequestDto
            {
                Category = MaintenanceCategory.Electrical,
                Priority = MaintenancePriority.Emergency,
                TriageNotes = "  Isolate the circuit immediately.  "
            });

        Assert.Equal(MaintenanceRequestStatus.Triaged, result.Status);
        Assert.Equal(MaintenanceCategory.Electrical, result.Category);
        Assert.Equal(MaintenancePriority.Emergency, result.Priority);
        Assert.Equal("Isolate the circuit immediately.", result.TriageNotes);
        Assert.NotNull(result.UpdatedAt);
    }

    [Fact]
    public async Task TriageAsync_RejectsRequestOutsideSubmittedState()
    {
        await using var context = CreateContext();
        var maintenanceRequest = AddRequest(context, status: MaintenanceRequestStatus.Assigned);
        await context.SaveChangesAsync();

        var exception = await Assert.ThrowsAsync<MaintenanceRequestServiceException>(() =>
            new MaintenanceRequestService(context).TriageAsync(
                maintenanceRequest.Id,
                new TriageMaintenanceRequestDto
                {
                    Category = MaintenanceCategory.Plumbing,
                    Priority = MaintenancePriority.Normal
                }));

        Assert.Equal(MaintenanceRequestServiceError.Conflict, exception.Error);
    }

    [Fact]
    public async Task AssignTechnicianAsync_AssignsTechnicianToTriagedRequest()
    {
        await using var context = CreateContext();
        var maintenanceRequest = AddRequest(context, status: MaintenanceRequestStatus.Triaged);
        await context.SaveChangesAsync();
        var technicianId = Guid.NewGuid();
        context.Users.Add(new ApplicationUser { Id = technicianId, FullName = "Technician", Role = UserRole.MaintenanceTechnician, IsActive = true });
        await context.SaveChangesAsync();

        var result = await new MaintenanceRequestService(context).AssignTechnicianAsync(
            maintenanceRequest.Id,
            new AssignTechnicianDto
            {
                TechnicianId = technicianId,
                AssignmentNotes = "  Bring replacement fittings.  "
            });

        Assert.Equal(MaintenanceRequestStatus.Assigned, result.Status);
        Assert.Equal(technicianId, result.TechnicianId);
        Assert.Equal("Bring replacement fittings.", result.AssignmentNotes);
        Assert.NotNull(result.UpdatedAt);
    }

    [Fact]
    public async Task AssignTechnicianAsync_RejectsEmptyTechnicianId()
    {
        await using var context = CreateContext();
        var maintenanceRequest = AddRequest(context, status: MaintenanceRequestStatus.Triaged);
        await context.SaveChangesAsync();

        var exception = await Assert.ThrowsAsync<MaintenanceRequestServiceException>(() =>
            new MaintenanceRequestService(context).AssignTechnicianAsync(
                maintenanceRequest.Id,
                new AssignTechnicianDto()));

        Assert.Equal(MaintenanceRequestServiceError.Validation, exception.Error);
    }

    [Theory]
    [InlineData(MaintenanceRequestStatus.Submitted)]
    [InlineData(MaintenanceRequestStatus.Completed)]
    [InlineData(MaintenanceRequestStatus.Cancelled)]
    public async Task AssignTechnicianAsync_RejectsRequestOutsideTriagedState(
        MaintenanceRequestStatus status)
    {
        await using var context = CreateContext();
        var maintenanceRequest = AddRequest(context, status: status);
        await context.SaveChangesAsync();

        var exception = await Assert.ThrowsAsync<MaintenanceRequestServiceException>(() =>
            new MaintenanceRequestService(context).AssignTechnicianAsync(
                maintenanceRequest.Id,
                new AssignTechnicianDto { TechnicianId = Guid.NewGuid() }));

        Assert.Equal(MaintenanceRequestServiceError.Conflict, exception.Error);
    }

    [Fact]
    public async Task CreateAsync_CreatesInitialSubmittedHistoryEntry()
    {
        await using var context = CreateContext();
        var tenantId = Guid.NewGuid();
        var request = CreateValidRequest();
        await MaintenanceTenancyFixture.SeedAsync(context, tenantId, request.PropertyId);

        var result = await new MaintenanceRequestService(context)
            .CreateAsync(tenantId, request);

        var history = await context.MaintenanceStatusHistories.SingleAsync();
        Assert.Equal(result.Id, history.MaintenanceRequestId);
        Assert.Null(history.FromStatus);
        Assert.Equal(MaintenanceRequestStatus.Submitted, history.ToStatus);
        Assert.Equal(tenantId, history.ChangedByUserId);
    }

    [Fact]
    public async Task TriageAsync_CreatesSubmittedToTriagedHistoryEntry()
    {
        await using var context = CreateContext();
        var maintenanceRequest = AddRequest(context);
        await context.SaveChangesAsync();

        await new MaintenanceRequestService(context).TriageAsync(
            maintenanceRequest.Id,
            new TriageMaintenanceRequestDto
            {
                Category = MaintenanceCategory.Plumbing,
                Priority = MaintenancePriority.High,
                TriageNotes = "Urgent water damage risk."
            });

        var history = await context.MaintenanceStatusHistories.SingleAsync();
        Assert.Equal(MaintenanceRequestStatus.Submitted, history.FromStatus);
        Assert.Equal(MaintenanceRequestStatus.Triaged, history.ToStatus);
        Assert.Equal("Urgent water damage risk.", history.Notes);
    }

    [Fact]
    public async Task AssignTechnicianAsync_CreatesTriagedToAssignedHistoryEntry()
    {
        await using var context = CreateContext();
        var maintenanceRequest = AddRequest(context, status: MaintenanceRequestStatus.Triaged);
        await context.SaveChangesAsync();

        var technicianId = Guid.NewGuid();
        context.Users.Add(new ApplicationUser { Id = technicianId, FullName = "Technician", Role = UserRole.MaintenanceTechnician, IsActive = true });
        await context.SaveChangesAsync();
        await new MaintenanceRequestService(context).AssignTechnicianAsync(
            maintenanceRequest.Id,
            new AssignTechnicianDto
            {
                TechnicianId = technicianId,
                AssignmentNotes = "Take replacement washers."
            });

        var history = await context.MaintenanceStatusHistories.SingleAsync();
        Assert.Equal(MaintenanceRequestStatus.Triaged, history.FromStatus);
        Assert.Equal(MaintenanceRequestStatus.Assigned, history.ToStatus);
        Assert.Equal("Take replacement washers.", history.Notes);
    }

    [Fact]
    public async Task UpdateTenantRequestAsync_DoesNotCreateHistoryWhenStatusIsUnchanged()
    {
        await using var context = CreateContext();
        var service = new MaintenanceRequestService(context);
        var tenantId = Guid.NewGuid();
        var request = CreateValidRequest();
        await MaintenanceTenancyFixture.SeedAsync(context, tenantId, request.PropertyId);
        var maintenanceRequest = await service.CreateAsync(tenantId, request);

        await service.UpdateTenantRequestAsync(
            maintenanceRequest.Id,
            tenantId,
            CreateValidUpdate());

        Assert.Equal(1, await context.MaintenanceStatusHistories.CountAsync());
        var history = await context.MaintenanceStatusHistories.SingleAsync();
        Assert.Null(history.FromStatus);
        Assert.Equal(MaintenanceRequestStatus.Submitted, history.ToStatus);
    }

    [Fact]
    public async Task GetHistoryAsync_ReturnsHistoryInChronologicalOrder()
    {
        await using var context = CreateContext();
        var maintenanceRequest = AddRequest(context);
        var firstId = Guid.NewGuid();
        var secondId = Guid.NewGuid();
        var firstChangedAt = DateTimeOffset.UtcNow.AddMinutes(-2);
        var secondChangedAt = DateTimeOffset.UtcNow.AddMinutes(-1);
        context.MaintenanceStatusHistories.AddRange(
            new MaintenanceStatusHistory
            {
                Id = secondId,
                MaintenanceRequest = maintenanceRequest,
                FromStatus = MaintenanceRequestStatus.Submitted,
                ToStatus = MaintenanceRequestStatus.Triaged,
                ChangedAt = secondChangedAt
            },
            new MaintenanceStatusHistory
            {
                Id = firstId,
                MaintenanceRequest = maintenanceRequest,
                FromStatus = null,
                ToStatus = MaintenanceRequestStatus.Submitted,
                ChangedAt = firstChangedAt
            });
        await context.SaveChangesAsync();

        var history = await new MaintenanceRequestService(context)
            .GetHistoryAsync(maintenanceRequest.Id);

        Assert.Equal([firstId, secondId], history.Select(item => item.Id));
    }

    [Fact]
    public async Task GetHistoryAsync_ProjectsActorDisplayNamesAndRoles()
    {
        await using var context = CreateContext();
        var actorId = Guid.NewGuid();
        var request = AddRequest(context);
        context.Users.Add(CreateUser(actorId, UserRole.Landlord, true, "Landlord User"));
        context.MaintenanceStatusHistories.Add(new MaintenanceStatusHistory
        {
            Id = Guid.NewGuid(),
            MaintenanceRequest = request,
            ToStatus = MaintenanceRequestStatus.Triaged,
            ChangedByUserId = actorId,
            ChangedAt = DateTimeOffset.UtcNow
        });
        await context.SaveChangesAsync();

        var result = await new MaintenanceRequestService(context).GetHistoryAsync(request.Id);

        var entry = Assert.Single(result);
        Assert.Equal("Landlord User", entry.ChangedByName);
        Assert.Equal(UserRole.Landlord, entry.ChangedByRole);
    }

    [Fact]
    public async Task TriageAsync_DoesNotPersistHistoryWhenTransitionFails()
    {
        await using var context = CreateContext();
        var maintenanceRequest = AddRequest(context, status: MaintenanceRequestStatus.Assigned);
        await context.SaveChangesAsync();

        await Assert.ThrowsAsync<MaintenanceRequestServiceException>(() =>
            new MaintenanceRequestService(context).TriageAsync(
                maintenanceRequest.Id,
                new TriageMaintenanceRequestDto
                {
                    Category = MaintenanceCategory.Plumbing,
                    Priority = MaintenancePriority.Normal
                }));

        Assert.Empty(context.MaintenanceStatusHistories);
    }

    [Fact]
    public async Task SubmitEstimateAsync_CreatesServerCalculatedEstimateAndStatusHistory()
    {
        await using var context = CreateContext();
        var technicianId = Guid.NewGuid();
        var maintenanceRequest = await AddEstimatePendingRequestAsync(context, technicianId);
        var service = new MaintenanceRequestService(context);

        var estimate = await service.SubmitEstimateAsync(
            maintenanceRequest.Id,
            technicianId,
            new SubmitRepairEstimateDto { LaborCost = 125.50m, PartsCost = 50m, AdditionalCost = 24.50m });

        Assert.Equal(1, estimate.VersionNumber);
        Assert.Equal(200m, estimate.TotalCost);
        Assert.Equal(RepairEstimateStatus.Submitted, estimate.Status);
        Assert.Equal(MaintenanceRequestStatus.EstimateSubmitted, maintenanceRequest.Status);
        var history = await context.MaintenanceStatusHistories.OrderBy(item => item.ChangedAt).LastAsync();
        Assert.Equal(MaintenanceRequestStatus.EstimatePending, history.FromStatus);
        Assert.Equal(MaintenanceRequestStatus.EstimateSubmitted, history.ToStatus);
        Assert.Equal(technicianId, history.ChangedByUserId);
    }

    [Fact]
    public async Task SubmitEstimateAsync_RejectsWrongTechnicianAndNegativeCosts()
    {
        await using var context = CreateContext();
        var technicianId = Guid.NewGuid();
        var maintenanceRequest = await AddEstimatePendingRequestAsync(context, technicianId);
        var service = new MaintenanceRequestService(context);

        var wrongTechnician = await Assert.ThrowsAsync<MaintenanceRequestServiceException>(() =>
            service.SubmitEstimateAsync(maintenanceRequest.Id, Guid.NewGuid(), CreateEstimate()));
        Assert.Equal(MaintenanceRequestServiceError.Conflict, wrongTechnician.Error);

        var negativeCost = await Assert.ThrowsAsync<MaintenanceRequestServiceException>(() =>
            service.SubmitEstimateAsync(
                maintenanceRequest.Id,
                technicianId,
                new SubmitRepairEstimateDto { LaborCost = -1m }));
        Assert.Equal(MaintenanceRequestServiceError.Validation, negativeCost.Error);
        Assert.Empty(context.RepairEstimates);
    }

    [Fact]
    public async Task SubmitEstimateForReviewAsync_TransitionsEstimateSubmittedToAwaitingApproval()
    {
        await using var context = CreateContext();
        var technicianId = Guid.NewGuid();
        var maintenanceRequest = await AddEstimatePendingRequestAsync(context, technicianId);
        var service = new MaintenanceRequestService(context);
        var estimate = await service.SubmitEstimateAsync(maintenanceRequest.Id, technicianId, CreateEstimate());

        var result = await service.SubmitEstimateForReviewAsync(maintenanceRequest.Id, estimate.Id);

        Assert.Equal(MaintenanceRequestStatus.AwaitingLandlordApproval, result.Status);
        Assert.Contains(await service.GetHistoryAsync(maintenanceRequest.Id), history =>
            history.FromStatus == MaintenanceRequestStatus.EstimateSubmitted
            && history.ToStatus == MaintenanceRequestStatus.AwaitingLandlordApproval);
    }

    [Fact]
    public async Task ApproveEstimateAsync_ApprovesEstimateAndRequest()
    {
        await using var context = CreateContext();
        var (service, maintenanceRequest, estimate) = await AddEstimateAwaitingReviewAsync(context);
        var landlordId = Guid.NewGuid();

        var result = await service.ApproveEstimateAsync(
            maintenanceRequest.Id,
            estimate.Id,
            landlordId,
            new ReviewRepairEstimateDto { ReviewNotes = "Approved." });

        Assert.Equal(RepairEstimateStatus.Approved, result.Status);
        Assert.Equal(MaintenanceRequestStatus.Approved, maintenanceRequest.Status);
        Assert.Contains(await service.GetHistoryAsync(maintenanceRequest.Id), history =>
            history.ToStatus == MaintenanceRequestStatus.Approved && history.ChangedByUserId == landlordId);
    }

    [Fact]
    public async Task RejectEstimateAsync_RequiresNotesAndRejectsRequest()
    {
        await using var context = CreateContext();
        var (service, maintenanceRequest, estimate) = await AddEstimateAwaitingReviewAsync(context);

        var missingNotes = await Assert.ThrowsAsync<MaintenanceRequestServiceException>(() =>
            service.RejectEstimateAsync(
                maintenanceRequest.Id,
                estimate.Id,
                Guid.NewGuid(),
                new ReviewRepairEstimateDto()));
        Assert.Equal(MaintenanceRequestServiceError.Validation, missingNotes.Error);

        var result = await service.RejectEstimateAsync(
            maintenanceRequest.Id,
            estimate.Id,
            Guid.NewGuid(),
            new ReviewRepairEstimateDto { ReviewNotes = "Cost exceeds approved budget." });
        Assert.Equal(RepairEstimateStatus.Rejected, result.Status);
        Assert.Equal(MaintenanceRequestStatus.Rejected, maintenanceRequest.Status);
    }

    [Fact]
    public async Task RequestEstimateRevisionAsync_PreservesOldEstimateAndNewSubmissionCreatesNewVersion()
    {
        await using var context = CreateContext();
        var (service, maintenanceRequest, firstEstimate) = await AddEstimateAwaitingReviewAsync(context);
        var technicianId = maintenanceRequest.TechnicianId!.Value;

        await service.RequestEstimateRevisionAsync(
            maintenanceRequest.Id,
            firstEstimate.Id,
            Guid.NewGuid(),
            new ReviewRepairEstimateDto { ReviewNotes = "Provide a lower-cost alternative." });

        Assert.Equal(MaintenanceRequestStatus.EstimatePending, maintenanceRequest.Status);
        Assert.Equal(RepairEstimateStatus.RevisionRequested, firstEstimate.Status);

        var secondEstimate = await service.SubmitEstimateAsync(
            maintenanceRequest.Id,
            technicianId,
            new SubmitRepairEstimateDto { LaborCost = 90m, PartsCost = 25m });

        Assert.Equal(2, secondEstimate.VersionNumber);
        var estimates = await service.GetEstimatesAsync(maintenanceRequest.Id);
        Assert.Equal([firstEstimate.Id, secondEstimate.Id], estimates.Select(item => item.Id));
        Assert.Equal(RepairEstimateStatus.RevisionRequested, estimates[0].Status);
        Assert.Equal("Provide a lower-cost alternative.", estimates[0].ReviewNotes);
        Assert.Equal(secondEstimate.Id, (await service.GetLatestEstimateAsync(maintenanceRequest.Id))!.Id);
    }

    [Fact]
    public async Task EstimateOperations_RejectInvalidRequestStates()
    {
        await using var context = CreateContext();
        var maintenanceRequest = AddRequest(context, status: MaintenanceRequestStatus.Assigned);
        maintenanceRequest.TechnicianId = Guid.NewGuid();
        await context.SaveChangesAsync();
        var service = new MaintenanceRequestService(context);

        var invalidSubmission = await Assert.ThrowsAsync<MaintenanceRequestServiceException>(() =>
            service.SubmitEstimateAsync(maintenanceRequest.Id, maintenanceRequest.TechnicianId.Value, CreateEstimate()));
        Assert.Equal(MaintenanceRequestServiceError.Conflict, invalidSubmission.Error);

        var markedPending = await service.MarkEstimatePendingAsync(maintenanceRequest.Id);
        Assert.Equal(MaintenanceRequestStatus.EstimatePending, markedPending.Status);

        var invalidReview = await Assert.ThrowsAsync<MaintenanceRequestServiceException>(() =>
            service.ApproveEstimateAsync(
                maintenanceRequest.Id,
                Guid.NewGuid(),
                Guid.NewGuid(),
                new ReviewRepairEstimateDto()));
        Assert.Equal(MaintenanceRequestServiceError.Conflict, invalidReview.Error);
    }

    [Fact]
    public async Task StartWorkAsync_AllowsAssignedTechnicianToStartApprovedRequest()
    {
        await using var context = CreateContext();
        var technicianId = Guid.NewGuid();
        var maintenanceRequest = AddRequest(context, technicianId: technicianId, status: MaintenanceRequestStatus.Approved);
        await context.SaveChangesAsync();

        var result = await new MaintenanceRequestService(context).StartWorkAsync(maintenanceRequest.Id, technicianId);

        Assert.Equal(MaintenanceRequestStatus.InProgress, result.Status);
        Assert.Equal(technicianId, result.TechnicianId);
    }

    [Fact]
    public async Task StartWorkAsync_ChangesStatusToInProgress()
    {
        await using var context = CreateContext();
        var technicianId = Guid.NewGuid();
        var maintenanceRequest = AddRequest(context, technicianId: technicianId, status: MaintenanceRequestStatus.Approved);
        await context.SaveChangesAsync();

        var result = await new MaintenanceRequestService(context).StartWorkAsync(maintenanceRequest.Id, technicianId);

        Assert.Equal(MaintenanceRequestStatus.InProgress, result.Status);
    }

    [Fact]
    public async Task StartWorkAsync_CreatesHistoryEntry()
    {
        await using var context = CreateContext();
        var technicianId = Guid.NewGuid();
        var maintenanceRequest = AddRequest(context, technicianId: technicianId, status: MaintenanceRequestStatus.Approved);
        await context.SaveChangesAsync();

        await new MaintenanceRequestService(context).StartWorkAsync(maintenanceRequest.Id, technicianId);

        var history = await context.MaintenanceStatusHistories.OrderBy(item => item.ChangedAt).LastAsync();
        Assert.Equal(MaintenanceRequestStatus.Approved, history.FromStatus);
        Assert.Equal(MaintenanceRequestStatus.InProgress, history.ToStatus);
        Assert.Equal(technicianId, history.ChangedByUserId);
    }

    [Fact]
    public async Task StartWorkAsync_RejectsUnauthorizedTechnician()
    {
        await using var context = CreateContext();
        var technicianId = Guid.NewGuid();
        var maintenanceRequest = AddRequest(context, technicianId: technicianId, status: MaintenanceRequestStatus.Approved);
        await context.SaveChangesAsync();

        var exception = await Assert.ThrowsAsync<MaintenanceRequestServiceException>(() =>
            new MaintenanceRequestService(context).StartWorkAsync(maintenanceRequest.Id, Guid.NewGuid()));

        Assert.Equal(MaintenanceRequestServiceError.Conflict, exception.Error);
    }

    [Fact]
    public async Task StartWorkAsync_RejectsRequestOutsideApprovedState()
    {
        await using var context = CreateContext();
        var technicianId = Guid.NewGuid();
        var maintenanceRequest = AddRequest(context, technicianId: technicianId, status: MaintenanceRequestStatus.InProgress);
        AddCompletionEvidence(context, maintenanceRequest, technicianId);
        await context.SaveChangesAsync();

        var exception = await Assert.ThrowsAsync<MaintenanceRequestServiceException>(() =>
            new MaintenanceRequestService(context).StartWorkAsync(maintenanceRequest.Id, technicianId));

        Assert.Equal(MaintenanceRequestServiceError.Conflict, exception.Error);
    }

    [Fact]
    public async Task CompleteWorkAsync_AllowsAssignedTechnicianToCompleteInProgressRequest()
    {
        await using var context = CreateContext();
        var technicianId = Guid.NewGuid();
        var maintenanceRequest = AddRequest(context, technicianId: technicianId, status: MaintenanceRequestStatus.InProgress);
        AddCompletionEvidence(context, maintenanceRequest, technicianId);
        await context.SaveChangesAsync();

        var result = await new MaintenanceRequestService(context).CompleteWorkAsync(maintenanceRequest.Id, technicianId);

        Assert.Equal(MaintenanceRequestStatus.Completed, result.Status);
        Assert.Equal(technicianId, result.TechnicianId);
        Assert.NotNull(result.CompletedAt);
    }

    [Fact]
    public async Task CompleteWorkAsync_ChangesStatusToCompleted()
    {
        await using var context = CreateContext();
        var technicianId = Guid.NewGuid();
        var maintenanceRequest = AddRequest(context, technicianId: technicianId, status: MaintenanceRequestStatus.InProgress);
        AddCompletionEvidence(context, maintenanceRequest, technicianId);
        await context.SaveChangesAsync();

        var result = await new MaintenanceRequestService(context).CompleteWorkAsync(maintenanceRequest.Id, technicianId);

        Assert.Equal(MaintenanceRequestStatus.Completed, result.Status);
    }

    [Fact]
    public async Task CompleteWorkAsync_SetsCompletedAt()
    {
        await using var context = CreateContext();
        var technicianId = Guid.NewGuid();
        var maintenanceRequest = AddRequest(context, technicianId: technicianId, status: MaintenanceRequestStatus.InProgress);
        AddCompletionEvidence(context, maintenanceRequest, technicianId);
        await context.SaveChangesAsync();

        var result = await new MaintenanceRequestService(context).CompleteWorkAsync(maintenanceRequest.Id, technicianId);

        Assert.NotNull(result.CompletedAt);
    }

    [Fact]
    public async Task CompleteWorkAsync_CreatesHistoryEntry()
    {
        await using var context = CreateContext();
        var technicianId = Guid.NewGuid();
        var maintenanceRequest = AddRequest(context, technicianId: technicianId, status: MaintenanceRequestStatus.InProgress);
        AddCompletionEvidence(context, maintenanceRequest, technicianId);
        await context.SaveChangesAsync();

        await new MaintenanceRequestService(context).CompleteWorkAsync(maintenanceRequest.Id, technicianId);

        var history = await context.MaintenanceStatusHistories.OrderBy(item => item.ChangedAt).LastAsync();
        Assert.Equal(MaintenanceRequestStatus.InProgress, history.FromStatus);
        Assert.Equal(MaintenanceRequestStatus.Completed, history.ToStatus);
        Assert.Equal(technicianId, history.ChangedByUserId);
    }

    [Fact]
    public async Task CompleteWorkAsync_RejectsRequestOutsideInProgressState()
    {
        await using var context = CreateContext();
        var technicianId = Guid.NewGuid();
        var maintenanceRequest = AddRequest(context, technicianId: technicianId, status: MaintenanceRequestStatus.Approved);
        await context.SaveChangesAsync();

        var exception = await Assert.ThrowsAsync<MaintenanceRequestServiceException>(() =>
            new MaintenanceRequestService(context).CompleteWorkAsync(maintenanceRequest.Id, technicianId));

        Assert.Equal(MaintenanceRequestServiceError.Conflict, exception.Error);
    }

    [Fact]
    public async Task CompleteWorkAsync_RejectsUnauthorizedTechnician()
    {
        await using var context = CreateContext();
        var technicianId = Guid.NewGuid();
        var maintenanceRequest = AddRequest(context, technicianId: technicianId, status: MaintenanceRequestStatus.InProgress);
        await context.SaveChangesAsync();

        var exception = await Assert.ThrowsAsync<MaintenanceRequestServiceException>(() =>
            new MaintenanceRequestService(context).CompleteWorkAsync(maintenanceRequest.Id, Guid.NewGuid()));

        Assert.Equal(MaintenanceRequestServiceError.Conflict, exception.Error);
    }

    [Fact]
    public async Task CompleteWorkAsync_RequiresTechnicianCompletionEvidence()
    {
        await using var context = CreateContext();
        var technicianId = Guid.NewGuid();
        var maintenanceRequest = AddRequest(context, technicianId: technicianId, status: MaintenanceRequestStatus.InProgress);
        await context.SaveChangesAsync();

        var exception = await Assert.ThrowsAsync<MaintenanceRequestServiceException>(() =>
            new MaintenanceRequestService(context).CompleteWorkAsync(maintenanceRequest.Id, technicianId));

        Assert.Equal(MaintenanceRequestServiceError.Conflict, exception.Error);
        Assert.Equal(MaintenanceRequestStatus.InProgress, maintenanceRequest.Status);
    }

    [Fact]
    public async Task CompleteWorkAsync_TenantIssuePhotoDoesNotSatisfyCompletionEvidence()
    {
        await using var context = CreateContext();
        var technicianId = Guid.NewGuid();
        var maintenanceRequest = AddRequest(context, technicianId: technicianId, status: MaintenanceRequestStatus.InProgress);
        context.MaintenanceAttachments.Add(new MaintenanceAttachment
        {
            MaintenanceRequestId = maintenanceRequest.Id,
            StorageKey = "private-tenant-photo",
            FileName = "issue.jpg",
            ContentType = "image/jpeg",
            FileSize = 1,
            AttachmentType = "issue",
            UploadedByUserId = maintenanceRequest.TenantId
        });
        await context.SaveChangesAsync();

        var exception = await Assert.ThrowsAsync<MaintenanceRequestServiceException>(() =>
            new MaintenanceRequestService(context).CompleteWorkAsync(maintenanceRequest.Id, technicianId));

        Assert.Equal(MaintenanceRequestServiceError.Conflict, exception.Error);
    }

    private static SubmitRepairEstimateDto CreateEstimate() =>
        new() { LaborCost = 100m, PartsCost = 25m, AdditionalCost = 5m, Notes = "Replace worn fittings." };

    private static async Task<MaintenanceRequest> AddEstimatePendingRequestAsync(
        ApplicationDbContext context,
        Guid technicianId)
    {
        var maintenanceRequest = AddRequest(context, status: MaintenanceRequestStatus.EstimatePending);
        maintenanceRequest.TechnicianId = technicianId;
        await context.SaveChangesAsync();
        return maintenanceRequest;
    }

    private static async Task<(MaintenanceRequestService Service, MaintenanceRequest Request, RepairEstimate Estimate)>
        AddEstimateAwaitingReviewAsync(ApplicationDbContext context)
    {
        var technicianId = Guid.NewGuid();
        var maintenanceRequest = await AddEstimatePendingRequestAsync(context, technicianId);
        var service = new MaintenanceRequestService(context);
        var estimateResponse = await service.SubmitEstimateAsync(
            maintenanceRequest.Id,
            technicianId,
            CreateEstimate());
        await service.SubmitEstimateForReviewAsync(maintenanceRequest.Id, estimateResponse.Id);
        var estimate = await context.RepairEstimates.SingleAsync(item => item.Id == estimateResponse.Id);
        return (service, maintenanceRequest, estimate);
    }

    [Theory]
    [InlineData(UserRole.MaintenanceTechnician, false, true)]
    [InlineData(UserRole.Tenant, true, true)]
    [InlineData(UserRole.Landlord, true, true)]
    [InlineData(UserRole.Admin, true, true)]
    [InlineData(UserRole.MaintenanceTechnician, true, false)]
    public async Task Assignment_RejectsIneligibleIdentity(UserRole role, bool active, bool exists)
    {
        await using var context = CreateContext();
        var request = AddRequest(context, status: MaintenanceRequestStatus.Triaged);
        var technicianId = Guid.NewGuid();
        if (exists) context.Users.Add(new ApplicationUser { Id = technicianId, FullName = "Candidate", Role = role, IsActive = active });
        await context.SaveChangesAsync();
        var error = await Assert.ThrowsAsync<MaintenanceRequestServiceException>(() =>
            new MaintenanceRequestService(context).AssignTechnicianAsync(request.Id, new AssignTechnicianDto { TechnicianId = technicianId }));
        Assert.Equal(MaintenanceRequestServiceError.Validation, error.Error);
        Assert.Null(request.TechnicianId);
        Assert.Equal(MaintenanceRequestStatus.Triaged, request.Status);
        Assert.Empty(context.MaintenanceStatusHistories);
    }

    private static ApplicationDbContext CreateContext()
    {
        var options = new DbContextOptionsBuilder<ApplicationDbContext>()
            .UseInMemoryDatabase($"MaintenanceRequestServiceTests-{Guid.NewGuid()}")
            .Options;

        return new ApplicationDbContext(options);
    }

    private static ApplicationUser CreateUser(
        Guid id,
        UserRole role,
        bool isActive,
        string fullName)
    {
        var email = $"{id:N}@example.test";
        return new ApplicationUser
        {
            Id = id,
            FullName = fullName,
            Email = email,
            NormalizedEmail = email.ToUpperInvariant(),
            PhoneNumber = "+94770000000",
            Role = role,
            IsActive = isActive,
            CreatedAt = DateTimeOffset.UtcNow,
            UpdatedAt = DateTimeOffset.UtcNow
        };
    }

    private static CreateMaintenanceRequestDto CreateValidRequest() =>
        new()
        {
            PropertyId = Guid.NewGuid(),
            Title = "Leaking kitchen tap",
            Description = "Water is leaking from the kitchen tap whenever it is used.",
            Category = MaintenanceCategory.Plumbing,
            Priority = MaintenancePriority.Normal,
            PreferredAccessWindow = PreferredAccessWindow.Morning,
            TenantAccessNotes = "Please call before arriving."
        };

    private static UpdateMaintenanceRequestDto CreateValidUpdate() =>
        new()
        {
            Title = "Updated kitchen tap leak",
            Description = "The kitchen tap continues to leak.",
            Category = MaintenanceCategory.Plumbing,
            Priority = MaintenancePriority.Normal,
            TenantAccessNotes = "Please call before arriving."
        };

    private static MaintenanceRequest AddRequest(
        ApplicationDbContext context,
        Guid? tenantId = null,
        Guid? propertyId = null,
        Guid? technicianId = null,
        MaintenanceRequestStatus status = MaintenanceRequestStatus.Submitted)
    {
        var maintenanceRequest = new MaintenanceRequest
        {
            Id = Guid.NewGuid(),
            TenantId = tenantId ?? Guid.NewGuid(),
            PropertyId = propertyId ?? Guid.NewGuid(),
            TechnicianId = technicianId,
            Title = "Leaking kitchen tap",
            Description = "Water is leaking from the kitchen tap.",
            Category = MaintenanceCategory.Plumbing,
            Priority = MaintenancePriority.Normal,
            Status = status,
            CreatedAt = DateTimeOffset.UtcNow
        };

        context.MaintenanceRequests.Add(maintenanceRequest);
        return maintenanceRequest;
    }

    private static void AddCompletionEvidence(
        ApplicationDbContext context,
        MaintenanceRequest request,
        Guid technicianId) => context.MaintenanceAttachments.Add(new MaintenanceAttachment
        {
            MaintenanceRequestId = request.Id,
            StorageKey = $"completion/{Guid.NewGuid():N}",
            FileName = "completed.jpg",
            ContentType = "image/jpeg",
            FileSize = 1,
            AttachmentType = MaintenanceAttachmentService.TechnicianCompletionAttachmentType,
            UploadedByUserId = technicianId
        });
}
