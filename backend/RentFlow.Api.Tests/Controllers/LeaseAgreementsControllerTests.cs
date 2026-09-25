using Microsoft.AspNetCore.Mvc;
using RentFlow.Api.Controllers;
using RentFlow.Api.DTOs.LeaseAgreements;
using RentFlow.Api.Models;
using RentFlow.Api.Services;
using RentFlow.Api.Services.Interfaces;
using Xunit;

namespace RentFlow.Api.Tests.Controllers;

public class LeaseAgreementsControllerTests
{
    [Fact]
    public async Task Create_WhenSuccessful_ReturnsCreatedAtAction()
    {
        var expectedLease = new LeaseAgreementResponseDto
        {
            Id = Guid.NewGuid(),
            RentalOfferId = Guid.NewGuid(),
            TenantId = Guid.NewGuid(),
            PropertyId = Guid.NewGuid(),
            MonthlyRent = 85000m,
            SecurityDeposit = 170000m,
            StartDate = DateOnly.FromDateTime(DateTime.UtcNow.AddDays(10)),
            EndDate = DateOnly.FromDateTime(DateTime.UtcNow.AddYears(1)),
            Status = LeaseAgreementStatus.Pending,
            CreatedAt = DateTimeOffset.UtcNow
        };

        var leaseAgreementService = new StubLeaseAgreementService
        {
            CreateResult = expectedLease
        };

        var currentUserService = new StubCurrentUserService();

        var controller = new LeaseAgreementsController(
            leaseAgreementService,
            currentUserService,
            new StubPropertyAccessGuard());

        var dto = new CreateLeaseAgreementDto
        {
            RentalOfferId = expectedLease.RentalOfferId
        };

        var result = await controller.Create(
            dto,
            CancellationToken.None);

        var createdResult = Assert.IsType<CreatedAtActionResult>(result);

        Assert.Equal(
            nameof(LeaseAgreementsController.GetById),
            createdResult.ActionName);

        Assert.Equal(expectedLease, createdResult.Value);
    }

    [Fact]
    public async Task GetById_WhenLeaseExists_ReturnsOk()
    {
        var expectedLease = CreateLeaseResponse(
            LeaseAgreementStatus.Pending);

        var leaseAgreementService = new StubLeaseAgreementService
        {
            GetByIdResult = expectedLease
        };

        var controller = new LeaseAgreementsController(
            leaseAgreementService,
            new StubCurrentUserService { UserIdValue = expectedLease.TenantId },
            new StubPropertyAccessGuard());

        var result = await controller.GetById(
            expectedLease.Id,
            CancellationToken.None);

        var okResult = Assert.IsType<OkObjectResult>(result);

        Assert.Equal(expectedLease, okResult.Value);
    }

    [Fact]
    public async Task GetById_WhenLeaseDoesNotExist_ReturnsNotFound()
    {
        var leaseAgreementService = new StubLeaseAgreementService
        {
            GetByIdResult = null
        };

        var currentUserService = new StubCurrentUserService();

        var controller = new LeaseAgreementsController(
            leaseAgreementService,
            currentUserService,
            new StubPropertyAccessGuard());

        var result = await controller.GetById(
            Guid.NewGuid(),
            CancellationToken.None);

        Assert.IsType<NotFoundObjectResult>(result);
    }

    [Fact]
    public async Task GetMine_UsesAuthenticatedTenantId()
    {
        var tenantId = Guid.NewGuid();

        var expectedLeases = new List<LeaseAgreementResponseDto>
        {
            new()
            {
                Id = Guid.NewGuid(),
                RentalOfferId = Guid.NewGuid(),
                TenantId = tenantId,
                PropertyId = Guid.NewGuid(),
                MonthlyRent = 85000m,
                SecurityDeposit = 170000m,
                StartDate = DateOnly.FromDateTime(DateTime.UtcNow.AddDays(10)),
                EndDate = DateOnly.FromDateTime(DateTime.UtcNow.AddYears(1)),
                Status = LeaseAgreementStatus.Pending,
                CreatedAt = DateTimeOffset.UtcNow
            }
        };

        var leaseAgreementService = new StubLeaseAgreementService
        {
            GetByTenantResult = expectedLeases
        };

        var currentUserService = new StubCurrentUserService
        {
            UserIdValue = tenantId
        };

        var controller = new LeaseAgreementsController(
            leaseAgreementService,
            currentUserService,
            new StubPropertyAccessGuard());

        var result = await controller.GetMine(
            CancellationToken.None);

        var okResult = Assert.IsType<OkObjectResult>(result);

        Assert.Equal(expectedLeases, okResult.Value);
        Assert.Equal(tenantId, leaseAgreementService.LastTenantId);
    }

    [Fact]
    public async Task Activate_WhenSuccessful_ReturnsOk()
    {
        var expectedLease = CreateLeaseResponse(
            LeaseAgreementStatus.Active);

        var leaseAgreementService = new StubLeaseAgreementService
        {
            ActivateResult = expectedLease
        };

        var currentUserService = new StubCurrentUserService();

        var controller = new LeaseAgreementsController(
            leaseAgreementService,
            currentUserService,
            new StubPropertyAccessGuard());

        var result = await controller.Activate(
            expectedLease.Id,
            CancellationToken.None);

        var okResult = Assert.IsType<OkObjectResult>(result);

        Assert.Equal(expectedLease, okResult.Value);
    }

    [Fact]
    public async Task Terminate_WhenSuccessful_ReturnsOk()
    {
        var expectedLease = CreateLeaseResponse(
            LeaseAgreementStatus.Terminated);

        var leaseAgreementService = new StubLeaseAgreementService
        {
            TerminateResult = expectedLease
        };

        var currentUserService = new StubCurrentUserService();

        var controller = new LeaseAgreementsController(
            leaseAgreementService,
            currentUserService,
            new StubPropertyAccessGuard());

        var result = await controller.Terminate(
            expectedLease.Id,
            CancellationToken.None);

        var okResult = Assert.IsType<OkObjectResult>(result);

        Assert.Equal(expectedLease, okResult.Value);
    }

    [Fact]
    public async Task Complete_WhenSuccessful_ReturnsOk()
    {
        var expectedLease = CreateLeaseResponse(
            LeaseAgreementStatus.Completed);

        var leaseAgreementService = new StubLeaseAgreementService
        {
            CompleteResult = expectedLease
        };

        var currentUserService = new StubCurrentUserService();

        var controller = new LeaseAgreementsController(
            leaseAgreementService,
            currentUserService,
            new StubPropertyAccessGuard());

        var result = await controller.Complete(
            expectedLease.Id,
            CancellationToken.None);

        var okResult = Assert.IsType<OkObjectResult>(result);

        Assert.Equal(expectedLease, okResult.Value);
    }

    [Fact]
    public async Task Activate_WhenServiceThrowsConflict_ReturnsConflict()
    {
        var leaseAgreementService = new StubLeaseAgreementService
        {
            ActivateException = LeaseAgreementServiceException.Conflict(
                "Only pending lease agreements can be activated.")
        };

        var currentUserService = new StubCurrentUserService();

        var controller = new LeaseAgreementsController(
            leaseAgreementService,
            currentUserService,
            new StubPropertyAccessGuard());

        var result = await controller.Activate(
            Guid.NewGuid(),
            CancellationToken.None);

        Assert.IsType<ConflictObjectResult>(result);
    }

    private static LeaseAgreementResponseDto CreateLeaseResponse(
        LeaseAgreementStatus status)
    {
        return new LeaseAgreementResponseDto
        {
            Id = Guid.NewGuid(),
            RentalOfferId = Guid.NewGuid(),
            TenantId = Guid.NewGuid(),
            PropertyId = Guid.NewGuid(),
            MonthlyRent = 85000m,
            SecurityDeposit = 170000m,
            StartDate = DateOnly.FromDateTime(DateTime.UtcNow.AddDays(10)),
            EndDate = DateOnly.FromDateTime(DateTime.UtcNow.AddYears(1)),
            Status = status,
            CreatedAt = DateTimeOffset.UtcNow,
            UpdatedAt = DateTimeOffset.UtcNow
        };
    }

    private sealed class StubLeaseAgreementService : ILeaseAgreementService
    {
        public LeaseAgreementResponseDto? CreateResult { get; set; }

        public LeaseAgreementResponseDto? GetByIdResult { get; set; }

        public IReadOnlyList<LeaseAgreementResponseDto>? GetByTenantResult { get; set; }

        public LeaseAgreementResponseDto? ActivateResult { get; set; }

        public LeaseAgreementResponseDto? TerminateResult { get; set; }

        public LeaseAgreementResponseDto? CompleteResult { get; set; }

        public LeaseAgreementServiceException? ActivateException { get; set; }

        public Guid? LastTenantId { get; private set; }

        public Task<LeaseAgreementResponseDto> CreateAsync(
            CreateLeaseAgreementDto dto,
            CancellationToken cancellationToken = default)
        {
            return Task.FromResult(CreateResult!);
        }

        public Task<LeaseAgreementResponseDto?> GetByIdAsync(
            Guid id,
            CancellationToken cancellationToken = default)
        {
            return Task.FromResult(GetByIdResult);
        }

        public Task<IReadOnlyList<LeaseAgreementResponseDto>> GetByTenantAsync(
            Guid tenantId,
            CancellationToken cancellationToken = default)
        {
            LastTenantId = tenantId;

            return Task.FromResult(
                GetByTenantResult ?? Array.Empty<LeaseAgreementResponseDto>());
        }

        public Task<LeaseAgreementResponseDto> ActivateAsync(
            Guid leaseId,
            CancellationToken cancellationToken = default)
        {
            if (ActivateException is not null)
            {
                throw ActivateException;
            }

            return Task.FromResult(ActivateResult!);
        }

        public Task<LeaseAgreementResponseDto> TerminateAsync(
            Guid leaseId,
            CancellationToken cancellationToken = default)
        {
            return Task.FromResult(TerminateResult!);
        }

        public Task<LeaseAgreementResponseDto> CompleteAsync(
            Guid leaseId,
            CancellationToken cancellationToken = default)
        {
            return Task.FromResult(CompleteResult!);
        }
    }

    private sealed class StubCurrentUserService : ICurrentUserService
    {
        public bool IsAuthenticated => true;

        public Guid? UserIdValue { get; set; } = Guid.NewGuid();

        public Guid? UserId => UserIdValue;

        public UserRole? Role => RoleValue;

        public UserRole? RoleValue { get; set; } = UserRole.Tenant;
    }

    private sealed class StubPropertyAccessGuard : IPropertyAccessGuard
    {
        public Task<bool> CanAccessPropertyAsync(
            Guid landlordId, Guid propertyId, CancellationToken cancellationToken = default)
            => Task.FromResult(false);

        public Task<bool> CanAccessViewingAsync(
            Guid landlordId, Guid viewingId, CancellationToken cancellationToken = default)
            => Task.FromResult(false);

        public Task<bool> CanAccessApplicationAsync(
            Guid landlordId, Guid applicationId, CancellationToken cancellationToken = default)
            => Task.FromResult(false);

        public Task<bool> CanAccessRentalOfferAsync(
            Guid landlordId, Guid rentalOfferId, CancellationToken cancellationToken = default)
            => Task.FromResult(false);

        public Task<bool> CanAccessDocumentAsync(
            Guid landlordId, Guid documentId, CancellationToken cancellationToken = default)
            => Task.FromResult(false);

        public Task<bool> CanAccessWorkflowAsync(
            Guid landlordId, Guid workflowId, CancellationToken cancellationToken = default)
            => Task.FromResult(false);

        public Task<bool> CanAccessPricingAnalysisWorkflowAsync(
            Guid landlordId, Guid workflowId, CancellationToken cancellationToken = default)
            => Task.FromResult(false);
    }
}
