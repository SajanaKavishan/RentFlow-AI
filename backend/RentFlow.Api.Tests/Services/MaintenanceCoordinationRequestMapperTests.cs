using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using RentFlow.Api.Data;
using RentFlow.Api.DTOs.Maintenance;
using RentFlow.Api.Models;
using RentFlow.Api.Services;
using RentFlow.Api.Services.Interfaces;
using Xunit;

namespace RentFlow.Api.Tests.Services;

public class MaintenanceCoordinationRequestMapperTests
{
    public static IEnumerable<object[]> DomainValues() =>
        from status in Enum.GetValues<MaintenanceRequestStatus>()
        from category in Enum.GetValues<MaintenanceCategory>()
        from priority in Enum.GetValues<MaintenancePriority>()
        select new object[] { status, category, priority };

    [Theory]
    [MemberData(nameof(DomainValues))]
    public void MapsCanonicalDomainNames(MaintenanceRequestStatus status, MaintenanceCategory category, MaintenancePriority priority)
    {
        var request = new MaintenanceRequest { Title = "Issue", Description = "Description", Status = status, Category = category, Priority = priority };
        var payload = MaintenanceCoordinationRequestMapper.Map(request, null, []);
        Assert.Equal(status.ToString(), payload.CurrentStatus);
        Assert.Equal(category.ToString(), payload.Category);
        Assert.Equal(priority.ToString(), payload.Priority);
    }

    [Fact]
    public void MapsOnlyBoundedRedactedUsefulEvidenceWithoutCurrency()
    {
        var request = new MaintenanceRequest
        {
            Title = "  Leak tenant@example.com  ",
            Description = "Call +94771234567; https://private.example/photo for leak.",
            TenantAccessNotes = "secret entry code", TechnicianId = Guid.NewGuid(),
            PreferredAccessWindow = PreferredAccessWindow.Evening
        };
        var estimate = new RepairEstimate
        {
            VersionNumber = 2, LaborCost = 100000000m, PartsCost = 20m, AdditionalCost = 3m,
            TotalCost = 100000023m, Notes = new string('n', 4000), Status = RepairEstimateStatus.Submitted
        };
        var payload = MaintenanceCoordinationRequestMapper.Map(request, estimate, [new MaintenanceAttachment
        {
            FileName = "tenant-private-name.jpg", ContentType = "image/jpeg", FileSize = 50, StorageKey = "private-key", UploadedByUserId = Guid.NewGuid()
        }]);
        var json = JsonSerializer.Serialize(payload, new JsonSerializerOptions(JsonSerializerDefaults.Web));
        Assert.True(payload.HasAssignedTechnician);
        Assert.Equal("Evening", payload.PreferredAccessWindow);
        Assert.Equal(estimate.TotalCost, payload.RepairEstimate!.TotalCost);
        Assert.Equal(4000, payload.RepairEstimate.Notes!.Length);
        foreach (var excluded in new[] { "tenant@example.com", "+94771234567", "https://", "tenant-private-name", "private-key", "secret entry code", "currency", "tenantId", "uploadedByUserId", "assignedTechnicianId" })
            Assert.DoesNotContain(excluded, json, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task BothAnalysisPathsProduceIdenticalPayloadsForAllStatuses()
    {
        await using var context = new ApplicationDbContext(new DbContextOptionsBuilder<ApplicationDbContext>().UseInMemoryDatabase(Guid.NewGuid().ToString()).Options);
        var request = new MaintenanceRequest { Title = "Issue", Description = "Leak", PropertyId = Guid.NewGuid(), TenantId = Guid.NewGuid() };
        context.MaintenanceRequests.Add(request);
        await context.SaveChangesAsync();
        var client = new RecordingAgent();
        foreach (var status in Enum.GetValues<MaintenanceRequestStatus>())
        {
            request.Status = status;
            await context.SaveChangesAsync();
            await new MaintenanceCoordinationService(context, client).AnalyzeAsync(request.Id);
            var ephemeral = client.LastJson;
            await new MaintenanceCoordinationOrchestrator(context, new MaintenanceRequestDataValidationTool(),
                new MaintenanceCoordinationRuleTool(), client, TimeProvider.System,
                Microsoft.Extensions.Logging.Abstractions.NullLogger<MaintenanceCoordinationOrchestrator>.Instance).StartAnalysisAsync(request.Id);
            Assert.Equal(ephemeral, client.LastJson);
        }
    }

    private sealed class RecordingAgent : IMaintenanceCoordinationAgentClient
    {
        public string? LastJson { get; private set; }
        public Task<MaintenanceCoordinationAgentResponse> AnalyzeAsync(MaintenanceCoordinationAgentRequest request, CancellationToken cancellationToken = default)
        {
            LastJson = JsonSerializer.Serialize(request);
            return Task.FromResult(MaintenanceCoordinationTestData.Response(request));
        }
    }
}
