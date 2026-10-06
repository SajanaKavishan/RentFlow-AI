using RentFlow.Api.Tests.Services;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using RentFlow.Api.Data;
using RentFlow.Api.DTOs.Maintenance;
using RentFlow.Api.Models;
using RentFlow.Api.Services.Interfaces;
using RentFlow.Api.Tests.Authentication;
using Xunit;

namespace RentFlow.Api.Tests.Controllers;

public sealed class MaintenanceCoordinationWorkflowResponseTests
{
    private const string ValidPassword = "Secure1!Password";

    [Fact]
    public async Task StartCoordinationWorkflow_ReturnsCreatedSerializableWorkflowResponse()
    {
        var agentClient = new StubMaintenanceCoordinationAgentClient();
        using var factory = new AuthApiFactory
        {
            MaintenanceCoordinationAgentClient = agentClient
        };
        using var client = factory.CreateHttpsClient();
        var maintenanceRequestId = Guid.NewGuid();
        var landlordId = await AuthenticateAsLandlordAsync(client);
        await SeedMaintenanceRequestAsync(factory, maintenanceRequestId, landlordId);

        using var response = await client.PostAsync(
            $"/api/maintenance-requests/{maintenanceRequestId}/coordination-workflows",
            content: null);
        var responseBody = await response.Content.ReadAsStringAsync();

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        Assert.Equal(1, agentClient.CallCount);

        using var document = JsonDocument.Parse(responseBody);
        var workflow = document.RootElement;
        Assert.Equal(maintenanceRequestId, workflow.GetProperty("maintenanceRequestId").GetGuid());
        Assert.Equal(
            (int)MaintenanceCoordinationWorkflowStatus.AwaitingHumanReview,
            workflow.GetProperty("status").GetInt32());
        Assert.True(workflow.GetProperty("requiresHumanApproval").GetBoolean());
        Assert.Equal(
            (int)MaintenanceCoordinationApprovalStatus.Pending,
            workflow.GetProperty("approvalStatus").GetInt32());

        var steps = workflow.GetProperty("steps");
        Assert.Equal(3, steps.GetArrayLength());
        foreach (var step in steps.EnumerateArray())
        {
            Assert.False(step.TryGetProperty("workflow", out _));
        }

        var workflowId = workflow.GetProperty("id").GetGuid();
        using var getResponse = await client.GetAsync(
            $"/api/maintenance-requests/{maintenanceRequestId}/coordination-workflows/{workflowId}");
        var getResponseBody = await getResponse.Content.ReadAsStringAsync();

        Assert.Equal(HttpStatusCode.OK, getResponse.StatusCode);
        using var getDocument = JsonDocument.Parse(getResponseBody);
        var persistedWorkflow = getDocument.RootElement;
        Assert.Equal(workflowId, persistedWorkflow.GetProperty("id").GetGuid());
        Assert.Equal(maintenanceRequestId, persistedWorkflow.GetProperty("maintenanceRequestId").GetGuid());
        Assert.Equal(
            (int)MaintenanceCoordinationWorkflowStatus.AwaitingHumanReview,
            persistedWorkflow.GetProperty("status").GetInt32());
        Assert.True(persistedWorkflow.GetProperty("requiresHumanApproval").GetBoolean());

        var persistedSteps = persistedWorkflow.GetProperty("steps");
        Assert.Equal(3, persistedSteps.GetArrayLength());
        foreach (var step in persistedSteps.EnumerateArray())
        {
            Assert.False(step.TryGetProperty("workflow", out _));
            Assert.True(step.TryGetProperty("stepName", out _));
            Assert.True(step.TryGetProperty("stepOrder", out _));
            Assert.True(step.TryGetProperty("status", out _));
        }
    }

    private static async Task SeedMaintenanceRequestAsync(
        AuthApiFactory factory,
        Guid requestId, Guid landlordId)
    {
        using var scope = factory.Services.CreateScope();
        var dbContext = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
        var property = new Property { LandlordId = landlordId, Title = "Owned property", Address = "Test", City = "Test" };
        dbContext.Properties.Add(property);
        dbContext.MaintenanceRequests.Add(new MaintenanceRequest
        {
            Id = requestId,
            TenantId = Guid.NewGuid(),
            PropertyId = property.Id,
            Title = "Bathroom exhaust fan stopped working",
            Description = "The bathroom exhaust fan has stopped working and needs inspection.",
            Category = MaintenanceCategory.Electrical,
            Priority = MaintenancePriority.High,
            Status = MaintenanceRequestStatus.Submitted,
            CreatedAt = DateTimeOffset.UtcNow
        });
        await dbContext.SaveChangesAsync();
    }

    private static async Task<Guid> AuthenticateAsLandlordAsync(HttpClient client)
    {
        using var response = await client.PostAsJsonAsync("/api/auth/register", new
        {
            fullName = "Workflow Response Test Landlord",
            email = "coordination-response-test@example.com",
            phoneNumber = "+94770000000",
            password = ValidPassword,
            role = UserRole.Landlord.ToString()
        });
        Assert.True(response.IsSuccessStatusCode, await response.Content.ReadAsStringAsync());

        using var document = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue(
            "Bearer",
            document.RootElement.GetProperty("accessToken").GetString());
        return document.RootElement.GetProperty("user").GetProperty("id").GetGuid();
    }

    private sealed class StubMaintenanceCoordinationAgentClient : IMaintenanceCoordinationAgentClient
    {
        public int CallCount { get; private set; }

        public Task<MaintenanceCoordinationAgentResponse> AnalyzeAsync(
            MaintenanceCoordinationAgentRequest request,
            CancellationToken cancellationToken = default)
        {
            cancellationToken.ThrowIfCancellationRequested();
            CallCount++;

            return Task.FromResult(new MaintenanceCoordinationAgentResponse
            {
                MaintenanceRequestId = request.MaintenanceRequestId,
                Result = MaintenanceCoordinationTestData.Result(request),
                ExecutionMetadata = new MaintenanceCoordinationExecutionMetadata
                {
                    ExecutedSteps = ["plan", "classify_assess_issue", "assess_urgency", "review_maintenance_information", "produce_coordination_recommendation", "summarize"]
                }
            });
        }
    }
}
