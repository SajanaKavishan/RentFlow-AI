using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using RentFlow.Api.Data;
using RentFlow.Api.DTOs.Maintenance;
using RentFlow.Api.Models;
using RentFlow.Api.Services;
using RentFlow.Api.Services.Interfaces;
using Xunit;

namespace RentFlow.Api.Tests.Services;

public class MaintenanceCoordinationServiceTests
{
    [Fact]
    public async Task AnalyzeAsync_ReturnsAgentRecommendationAndDoesNotMutateMaintenanceState()
    {
        await using var context = CreateContext();
        var request = new MaintenanceRequest
        {
            Title = "Leaking tap",
            Description = "Water is leaking.",
            Category = MaintenanceCategory.Plumbing,
            Priority = MaintenancePriority.High,
            Status = MaintenanceRequestStatus.Assigned,
            TechnicianId = Guid.NewGuid()
        };
        context.MaintenanceRequests.Add(request);
        context.RepairEstimates.Add(new RepairEstimate
        {
            MaintenanceRequestId = request.Id,
            TechnicianId = request.TechnicianId.Value,
            VersionNumber = 1,
            TotalCost = 250m,
            Status = RepairEstimateStatus.Submitted
        });
        context.MaintenanceAttachments.Add(new MaintenanceAttachment
        {
            MaintenanceRequestId = request.Id,
            FileName = "leak.jpg",
            ContentType = "image/jpeg",
            FileSize = 1234,
            StorageKey = "private/not-forwarded",
            UploadedByUserId = Guid.NewGuid()
        });
        await context.SaveChangesAsync();
        var originalStatus = request.Status;
        var originalTechnician = request.TechnicianId;
        var agent = new FakeAgentClient();

        var result = await new MaintenanceCoordinationService(context, agent).AnalyzeAsync(request.Id);

        Assert.Equal("Plumbing", result.SuggestedCategory);
        Assert.Equal(originalStatus, request.Status);
        Assert.Equal(originalTechnician, request.TechnicianId);
        Assert.Equal(request.Id, agent.Request!.MaintenanceRequestId);
        Assert.Equal(250m, agent.Request.RepairEstimate!.TotalCost);
        var attachment = Assert.Single(agent.Request.Attachments);
        Assert.True(attachment.FileSize > 0);
        Assert.Equal("image/jpeg", attachment.ContentType);
        Assert.DoesNotContain("storageKey", JsonSerializer.Serialize(agent.Request), StringComparison.OrdinalIgnoreCase);

        var payload = JsonSerializer.SerializeToElement(agent.Request, new JsonSerializerOptions(JsonSerializerDefaults.Web));
        Assert.Equal(
            ["maintenanceRequestId", "title", "description", "category", "priority", "currentStatus", "preferredAccessWindow", "hasAssignedTechnician", "repairEstimate", "attachments"],
            payload.EnumerateObject().Select(property => property.Name).ToArray());
        Assert.Equal(
            ["attachmentId", "contentType", "fileSize"],
            payload.GetProperty("attachments")[0].EnumerateObject().Select(property => property.Name).ToArray());
        Assert.DoesNotContain(context.ChangeTracker.Entries(), entry =>
            entry.State is EntityState.Modified or EntityState.Added or EntityState.Deleted);
    }

    [Fact]
    public async Task AnalyzeAsync_MissingRequestThrowsNotFound()
    {
        await using var context = CreateContext();

        var exception = await Assert.ThrowsAsync<MaintenanceRequestServiceException>(() =>
            new MaintenanceCoordinationService(context, new FakeAgentClient()).AnalyzeAsync(Guid.NewGuid()));

        Assert.Equal(MaintenanceRequestServiceError.NotFound, exception.Error);
    }

    [Fact]
    public async Task AnalyzeAsync_PropagatesAgentFailureWithoutWritingState()
    {
        await using var context = CreateContext();
        var request = new MaintenanceRequest { Title = "Issue", Description = "Details" };
        context.MaintenanceRequests.Add(request);
        await context.SaveChangesAsync();
        var agent = new FakeAgentClient { Exception = new MaintenanceCoordinationAgentClientException(MaintenanceCoordinationAgentClientError.ServiceUnavailable, "unavailable") };

        await Assert.ThrowsAsync<MaintenanceCoordinationAgentClientException>(() =>
            new MaintenanceCoordinationService(context, agent).AnalyzeAsync(request.Id));

        Assert.Equal(MaintenanceRequestStatus.Submitted, await context.MaintenanceRequests.Select(x => x.Status).SingleAsync());
    }

    private static ApplicationDbContext CreateContext() => new(new DbContextOptionsBuilder<ApplicationDbContext>()
        .UseInMemoryDatabase($"MaintenanceCoordination-{Guid.NewGuid()}")
        .Options);

    private sealed class FakeAgentClient : IMaintenanceCoordinationAgentClient
    {
        public MaintenanceCoordinationAgentRequest? Request { get; private set; }
        public Exception? Exception { get; init; }

        public Task<MaintenanceCoordinationAgentResponse> AnalyzeAsync(MaintenanceCoordinationAgentRequest request, CancellationToken cancellationToken = default)
        {
            Request = request;
            if (Exception is not null) throw Exception;
            return Task.FromResult(new MaintenanceCoordinationAgentResponse
            {
                MaintenanceRequestId = request.MaintenanceRequestId,
                Result = MaintenanceCoordinationTestData.Result(request),
                ExecutionMetadata = MaintenanceCoordinationTestData.Metadata()
            });
        }
    }
}