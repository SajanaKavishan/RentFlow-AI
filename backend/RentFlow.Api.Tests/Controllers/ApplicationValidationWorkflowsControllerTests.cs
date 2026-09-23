using System.Text.Json;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Logging.Abstractions;
using RentFlow.Api.Controllers;
using RentFlow.Api.DTOs.ApplicationValidation;
using RentFlow.Api.Models;
using RentFlow.Api.Services;
using RentFlow.Api.Services.Interfaces;
using Xunit;

namespace RentFlow.Api.Tests.Controllers;

public class ApplicationValidationWorkflowsControllerTests
{
    [Fact]
    public async Task StartValidation_ReturnsCreatedWorkflow()
    {
        var applicationId = Guid.NewGuid();
        var workflow = CreateWorkflow(applicationId);
        var controller = CreateController(
            new StubOrchestrator((id, _) => Task.FromResult(workflow)),
            new StubQueryService());

        var response = await controller.StartValidation(applicationId, CancellationToken.None);

        var created = Assert.IsType<CreatedAtActionResult>(response.Result);
        Assert.Equal(StatusCodes.Status201Created, created.StatusCode);
        Assert.Equal(nameof(ApplicationValidationWorkflowsController.GetById), created.ActionName);
        Assert.Equal(workflow.Id, created.RouteValues!["workflowId"]);
        Assert.Same(workflow, created.Value);
    }

    [Fact]
    public async Task StartValidation_MapsIneligibleApplicationToSafeConflict()
    {
        var controller = CreateController(
            new StubOrchestrator((_, _) => throw new ApplicationValidationException(
                ApplicationValidationError.Conflict,
                "A Draft application is not eligible for validation.")),
            new StubQueryService());

        var response = await controller.StartValidation(Guid.NewGuid(), CancellationToken.None);

        var result = Assert.IsType<ObjectResult>(response.Result);
        Assert.Equal(StatusCodes.Status409Conflict, result.StatusCode);
        var problem = Assert.IsType<ProblemDetails>(result.Value);
        Assert.Equal("Application is not eligible for validation.", problem.Title);
        Assert.Equal("A Draft application is not eligible for validation.", problem.Detail);
        Assert.DoesNotContain("stack", JsonSerializer.Serialize(problem), StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task GetByApplication_ReturnsRunsFromQueryService()
    {
        var applicationId = Guid.NewGuid();
        var workflows = new[]
        {
            CreateWorkflow(applicationId, DateTimeOffset.UtcNow),
            CreateWorkflow(applicationId, DateTimeOffset.UtcNow.AddMinutes(-5))
        };
        var query = new StubQueryService { ByApplication = workflows };
        var controller = CreateController(new StubOrchestrator(), query);

        var response = await controller.GetByApplication(applicationId, CancellationToken.None);

        var ok = Assert.IsType<OkObjectResult>(response.Result);
        Assert.Same(workflows, ok.Value);
        Assert.Equal(applicationId, query.RequestedApplicationId);
    }

    [Fact]
    public async Task GetById_ReturnsWorkflowWithOrderedSteps()
    {
        var workflow = CreateWorkflow(Guid.NewGuid());
        var query = new StubQueryService { ById = workflow };
        var controller = CreateController(new StubOrchestrator(), query);

        var response = await controller.GetById(workflow.Id, CancellationToken.None);

        var ok = Assert.IsType<OkObjectResult>(response.Result);
        var returned = Assert.IsType<ApplicationValidationWorkflowResponseDto>(ok.Value);
        Assert.Equal(workflow.Id, returned.Id);
        Assert.Equal([1, 2], returned.Steps.Select(step => step.StepOrder));
    }

    [Fact]
    public async Task GetById_ReturnsNotFoundWhenWorkflowDoesNotExist()
    {
        var controller = CreateController(new StubOrchestrator(), new StubQueryService());

        var response = await controller.GetById(Guid.NewGuid(), CancellationToken.None);

        var result = Assert.IsType<ObjectResult>(response.Result);
        Assert.Equal(StatusCodes.Status404NotFound, result.StatusCode);
        var problem = Assert.IsType<ProblemDetails>(result.Value);
        Assert.Equal("Application validation resource not found.", problem.Title);
    }

    [Fact]
    public void WorkflowResponse_DoesNotExposePersistenceFieldsOrSerializedResultJson()
    {
        var json = JsonSerializer.Serialize(
            CreateWorkflow(Guid.NewGuid()),
            new JsonSerializerOptions(JsonSerializerDefaults.Web));

        Assert.DoesNotContain("storageKey", json, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("resultJson", json, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("inputSummary", json, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("stepId", json, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("\"result\":{", json, StringComparison.Ordinal);
    }

    private static ApplicationValidationWorkflowsController CreateController(
        IApplicationValidationOrchestrator orchestrator,
        IApplicationValidationQueryService queryService)
    {
        return new ApplicationValidationWorkflowsController(
            orchestrator,
            queryService,
            new AllowingPropertyAccessGuard(),
            new AdminCurrentUserService(),
            NullLogger<ApplicationValidationWorkflowsController>.Instance)
        {
            ControllerContext = new ControllerContext
            {
                HttpContext = new DefaultHttpContext()
            }
        };
    }

    private static ApplicationValidationWorkflowResponseDto CreateWorkflow(
        Guid applicationId,
        DateTimeOffset? createdAt = null)
    {
        var firstResult = JsonSerializer.Deserialize<JsonElement>("{\"isValid\":true}");
        var secondResult = JsonSerializer.Deserialize<JsonElement>("{\"passed\":true}");
        var timestamp = createdAt ?? DateTimeOffset.UtcNow;

        return new ApplicationValidationWorkflowResponseDto
        {
            Id = Guid.NewGuid(),
            ApplicationId = applicationId,
            Objective = "Validate application for landlord review.",
            Status = ApplicationValidationWorkflowStatus.AwaitingHumanReview,
            CurrentStep = 2,
            CompletenessScore = 100m,
            Recommendation = "Ready for landlord review",
            RequiresHumanApproval = true,
            CreatedAt = timestamp,
            UpdatedAt = timestamp,
            Steps =
            [
                new ApplicationValidationStepResponseDto
                {
                    AgentName = "Application Data Validator",
                    StepOrder = 1,
                    Status = ApplicationValidationStepStatus.Completed,
                    Result = firstResult,
                    StartedAt = timestamp,
                    CompletedAt = timestamp
                },
                new ApplicationValidationStepResponseDto
                {
                    AgentName = "Rule Checker",
                    StepOrder = 2,
                    Status = ApplicationValidationStepStatus.Completed,
                    Result = secondResult,
                    StartedAt = timestamp,
                    CompletedAt = timestamp
                }
            ]
        };
    }

    private sealed class StubOrchestrator(
        Func<Guid, CancellationToken, Task<ApplicationValidationWorkflowResponseDto>>? start = null)
        : IApplicationValidationOrchestrator
    {
        public Task<ApplicationValidationWorkflowResponseDto> StartValidationAsync(
            Guid applicationId,
            CancellationToken cancellationToken = default)
        {
            return start?.Invoke(applicationId, cancellationToken)
                ?? Task.FromResult(CreateWorkflow(applicationId));
        }
    }

    private sealed class StubQueryService : IApplicationValidationQueryService
    {
        public ApplicationValidationWorkflowResponseDto? ById { get; init; }

        public IReadOnlyList<ApplicationValidationWorkflowResponseDto> ByApplication { get; init; }
            = Array.Empty<ApplicationValidationWorkflowResponseDto>();

        public Guid? RequestedApplicationId { get; private set; }

        public Task<ApplicationValidationWorkflowResponseDto?> GetByIdAsync(
            Guid workflowId,
            CancellationToken cancellationToken = default)
        {
            return Task.FromResult(ById);
        }

        public Task<IReadOnlyList<ApplicationValidationWorkflowResponseDto>> GetByApplicationAsync(
            Guid applicationId,
            CancellationToken cancellationToken = default)
        {
            RequestedApplicationId = applicationId;
            return Task.FromResult(ByApplication);
        }
    }

    private sealed class AllowingPropertyAccessGuard : IPropertyAccessGuard
    {
        public Task<bool> CanAccessPropertyAsync(Guid landlordId, Guid propertyId,
            CancellationToken cancellationToken = default) => Task.FromResult(true);

        public Task<bool> CanAccessViewingAsync(Guid landlordId, Guid viewingId,
            CancellationToken cancellationToken = default) => Task.FromResult(true);

        public Task<bool> CanAccessApplicationAsync(Guid landlordId, Guid applicationId,
            CancellationToken cancellationToken = default) => Task.FromResult(true);

        public Task<bool> CanAccessRentalOfferAsync(Guid landlordId, Guid rentalOfferId,
            CancellationToken cancellationToken = default) => Task.FromResult(true);

        public Task<bool> CanAccessDocumentAsync(Guid landlordId, Guid documentId,
            CancellationToken cancellationToken = default) => Task.FromResult(true);

        public Task<bool> CanAccessWorkflowAsync(Guid landlordId, Guid workflowId,
            CancellationToken cancellationToken = default) => Task.FromResult(true);
    }

    private sealed class AdminCurrentUserService : ICurrentUserService
    {
        public bool IsAuthenticated => true;
        public Guid? UserId => Guid.NewGuid();
        public UserRole? Role => UserRole.Admin;
    }
}
