using System.Text.Json;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Logging.Abstractions;
using RentFlow.Api.Controllers;
using RentFlow.Api.DTOs.PricingAnalysis;
using RentFlow.Api.Models;
using RentFlow.Api.Services;
using RentFlow.Api.Services.Interfaces;
using Xunit;

namespace RentFlow.Api.Tests.Controllers;

public sealed class PricingAnalysisWorkflowsControllerTests
{
    [Fact]
    public async Task Start_ReturnsCreatedAndChecksLandlordPropertyAccess()
    {
        var propertyId = Guid.NewGuid();
        var workflow = CreateWorkflow(propertyId);
        var access = new StubPropertyAccessGuard { PropertyAccess = true };
        var orchestrator = new StubOrchestrator((id, _) =>
        {
            Assert.Equal(propertyId, id);
            return Task.FromResult(workflow);
        });
        var controller = CreateController(orchestrator, new StubQueryService(), access,
            new StubCurrentUser(UserRole.Landlord));

        var response = await controller.Start(propertyId, CancellationToken.None);

        var created = Assert.IsType<CreatedAtActionResult>(response.Result);
        Assert.Equal(StatusCodes.Status201Created, created.StatusCode);
        Assert.Equal(nameof(PricingAnalysisWorkflowsController.GetById), created.ActionName);
        Assert.Equal(workflow.WorkflowId, created.RouteValues!["workflowId"]);
        Assert.Same(workflow, created.Value);
        Assert.Equal(propertyId, access.CheckedPropertyId);
        Assert.Equal(1, orchestrator.Calls);
    }

    [Fact]
    public async Task Start_HidesPropertyOwnershipFailureAsNotFound()
    {
        var orchestrator = new StubOrchestrator();
        var controller = CreateController(orchestrator, new StubQueryService(),
            new StubPropertyAccessGuard(), new StubCurrentUser(UserRole.Landlord));

        var response = await controller.Start(Guid.NewGuid(), CancellationToken.None);

        AssertProblem(response.Result, StatusCodes.Status404NotFound);
        Assert.Equal(0, orchestrator.Calls);
    }

    [Fact]
    public async Task GetByProperty_ReturnsHistoryAndAdminBypassesOwnershipGuard()
    {
        var propertyId = Guid.NewGuid();
        var history = new[] { CreateWorkflow(propertyId) };
        var query = new StubQueryService { ByProperty = history };
        var access = new StubPropertyAccessGuard();
        var controller = CreateController(new StubOrchestrator(), query, access,
            new StubCurrentUser(UserRole.Admin));

        var response = await controller.GetByProperty(propertyId, CancellationToken.None);

        var ok = Assert.IsType<OkObjectResult>(response.Result);
        Assert.Same(history, ok.Value);
        Assert.Equal(propertyId, query.RequestedPropertyId);
        Assert.Null(access.CheckedPropertyId);
    }

    [Fact]
    public async Task GetById_EnforcesLandlordWorkflowAccessAndReturnsWorkflow()
    {
        var workflow = CreateWorkflow(Guid.NewGuid());
        var access = new StubPropertyAccessGuard { WorkflowAccess = true };
        var query = new StubQueryService { ById = workflow };
        var controller = CreateController(new StubOrchestrator(), query, access,
            new StubCurrentUser(UserRole.Landlord));

        var response = await controller.GetById(workflow.WorkflowId, CancellationToken.None);

        var ok = Assert.IsType<OkObjectResult>(response.Result);
        Assert.Same(workflow, ok.Value);
        Assert.Equal(workflow.WorkflowId, access.CheckedWorkflowId);
    }

    [Fact]
    public async Task GetById_HidesInaccessibleAndMissingWorkflowAsNotFound()
    {
        var inaccessibleController = CreateController(new StubOrchestrator(),
            new StubQueryService(), new StubPropertyAccessGuard(),
            new StubCurrentUser(UserRole.Landlord));
        AssertProblem((await inaccessibleController.GetById(Guid.NewGuid(), CancellationToken.None)).Result,
            StatusCodes.Status404NotFound);

        var missingController = CreateController(new StubOrchestrator(),
            new StubQueryService(), new StubPropertyAccessGuard(),
            new StubCurrentUser(UserRole.Admin));
        AssertProblem((await missingController.GetById(Guid.NewGuid(), CancellationToken.None)).Result,
            StatusCodes.Status404NotFound);
    }

    [Fact]
    public async Task Start_MapsValidationFailureToBadRequest()
    {
        var controller = CreateController(
            new StubOrchestrator((_, _) => throw new PricingAnalysisException(
                PricingAnalysisError.Validation, "A property ID is required.")),
            new StubQueryService(), new StubPropertyAccessGuard(),
            new StubCurrentUser(UserRole.Admin));

        var response = await controller.Start(Guid.Empty, CancellationToken.None);

        AssertProblem(response.Result, StatusCodes.Status400BadRequest);
    }

    [Fact]
    public async Task UnexpectedFailure_ReturnsGenericProblemWithoutInternalDetails()
    {
        var controller = CreateController(
            new StubOrchestrator((_, _) => throw new InvalidOperationException("provider response secret")),
            new StubQueryService(), new StubPropertyAccessGuard(),
            new StubCurrentUser(UserRole.Admin));

        var response = await controller.Start(Guid.NewGuid(), CancellationToken.None);

        var problem = AssertProblem(response.Result, StatusCodes.Status500InternalServerError);
        Assert.DoesNotContain("provider response secret", JsonSerializer.Serialize(problem));
    }

    [Fact]
    public void Controller_RestrictsClassAccessToLandlordsAndAdmins()
    {
        var authorization = Assert.Single(typeof(PricingAnalysisWorkflowsController)
            .GetCustomAttributes(typeof(Microsoft.AspNetCore.Authorization.AuthorizeAttribute), inherit: true)
            .Cast<Microsoft.AspNetCore.Authorization.AuthorizeAttribute>());

        Assert.Equal("Landlord,Admin", authorization.Roles);
    }

    private static ProblemDetails AssertProblem(ActionResult? actionResult, int statusCode)
    {
        var result = Assert.IsType<ObjectResult>(actionResult);
        Assert.Equal(statusCode, result.StatusCode);
        var problem = Assert.IsType<ProblemDetails>(result.Value);
        Assert.Equal(statusCode, problem.Status);
        return problem;
    }

    private static PricingAnalysisWorkflowsController CreateController(
        IPricingAnalysisOrchestrator orchestrator,
        IPricingAnalysisQueryService queryService,
        StubPropertyAccessGuard access,
        StubCurrentUser currentUser)
    {
        return new PricingAnalysisWorkflowsController(
            orchestrator, queryService, access, currentUser,
            NullLogger<PricingAnalysisWorkflowsController>.Instance)
        {
            ControllerContext = new ControllerContext { HttpContext = new DefaultHttpContext() }
        };
    }

    private static PricingAnalysisWorkflowResponseDto CreateWorkflow(Guid propertyId) => new()
    {
        WorkflowId = Guid.NewGuid(),
        PropertyId = propertyId,
        Status = PricingAnalysisWorkflowStatus.Completed,
        EvidencePolicyVersion = "pricing-v1"
    };

    private sealed class StubOrchestrator(
        Func<Guid, CancellationToken, Task<PricingAnalysisWorkflowResponseDto>>? start = null)
        : IPricingAnalysisOrchestrator
    {
        public int Calls { get; private set; }

        public Task<PricingAnalysisWorkflowResponseDto> StartAsync(
            Guid propertyId, CancellationToken cancellationToken = default)
        {
            Calls++;
            return start?.Invoke(propertyId, cancellationToken)
                ?? Task.FromResult(CreateWorkflow(propertyId));
        }
    }

    private sealed class StubQueryService : IPricingAnalysisQueryService
    {
        public PricingAnalysisWorkflowResponseDto? ById { get; init; }
        public IReadOnlyList<PricingAnalysisWorkflowResponseDto> ByProperty { get; init; } = [];
        public Guid? RequestedPropertyId { get; private set; }

        public Task<PricingAnalysisWorkflowResponseDto?> GetByIdAsync(
            Guid workflowId, CancellationToken cancellationToken = default) => Task.FromResult(ById);

        public Task<IReadOnlyList<PricingAnalysisWorkflowResponseDto>> GetByPropertyAsync(
            Guid propertyId, CancellationToken cancellationToken = default)
        {
            RequestedPropertyId = propertyId;
            return Task.FromResult(ByProperty);
        }
    }

    private sealed class StubPropertyAccessGuard : IPropertyAccessGuard
    {
        public bool PropertyAccess { get; init; }
        public bool WorkflowAccess { get; init; }
        public Guid? CheckedPropertyId { get; private set; }
        public Guid? CheckedWorkflowId { get; private set; }

        public Task<bool> CanAccessPropertyAsync(Guid landlordId, Guid propertyId,
            CancellationToken cancellationToken = default)
        {
            CheckedPropertyId = propertyId;
            return Task.FromResult(PropertyAccess);
        }

        public Task<bool> CanAccessPricingAnalysisWorkflowAsync(Guid landlordId, Guid workflowId,
            CancellationToken cancellationToken = default)
        {
            CheckedWorkflowId = workflowId;
            return Task.FromResult(WorkflowAccess);
        }

        public Task<bool> CanAccessViewingAsync(Guid landlordId, Guid viewingId,
            CancellationToken cancellationToken = default) => Task.FromResult(false);
        public Task<bool> CanAccessApplicationAsync(Guid landlordId, Guid applicationId,
            CancellationToken cancellationToken = default) => Task.FromResult(false);
        public Task<bool> CanAccessRentalOfferAsync(Guid landlordId, Guid rentalOfferId,
            CancellationToken cancellationToken = default) => Task.FromResult(false);
        public Task<bool> CanAccessDocumentAsync(Guid landlordId, Guid documentId,
            CancellationToken cancellationToken = default) => Task.FromResult(false);
        public Task<bool> CanAccessWorkflowAsync(Guid landlordId, Guid workflowId,
            CancellationToken cancellationToken = default) => Task.FromResult(false);
    }

    private sealed class StubCurrentUser(UserRole role) : ICurrentUserService
    {
        public bool IsAuthenticated => true;
        public Guid? UserId { get; } = Guid.NewGuid();
        public UserRole? Role { get; } = role;
    }
}
