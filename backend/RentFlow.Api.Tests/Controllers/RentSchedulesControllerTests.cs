using Microsoft.AspNetCore.Mvc;
using RentFlow.Api.Controllers;
using RentFlow.Api.DTOs.RentSchedules;
using RentFlow.Api.Models;
using RentFlow.Api.Services.Interfaces;
using Xunit;

namespace RentFlow.Api.Tests.Controllers;

public class RentSchedulesControllerTests
{
    [Fact]
    public async Task GenerateForLease_WhenSuccessful_ReturnsOk()
    {
        var leaseAgreementId = Guid.NewGuid();

        var expectedItems = new List<RentScheduleItemResponseDto>
        {
            new()
            {
                Id = Guid.NewGuid(),
                LeaseAgreementId = leaseAgreementId,
                DueDate = new DateOnly(2026, 10, 1),
                Amount = 85000m,
                Status = RentScheduleStatus.Pending,
                CreatedAt = DateTimeOffset.UtcNow
            }
        };

        var rentScheduleService = new StubRentScheduleService
        {
            GenerateResult = expectedItems
        };

        var currentUserService = new StubCurrentUserService();

        var controller = new RentSchedulesController(
            rentScheduleService,
            currentUserService);

        var result = await controller.GenerateForLease(
            leaseAgreementId,
            CancellationToken.None);

        var okResult = Assert.IsType<OkObjectResult>(result);

        Assert.Equal(expectedItems, okResult.Value);
    }

    [Fact]
    public async Task GetMine_UsesAuthenticatedTenantId()
    {
        var tenantId = Guid.NewGuid();

        var expectedItems = new List<RentScheduleItemResponseDto>
        {
            new()
            {
                Id = Guid.NewGuid(),
                LeaseAgreementId = Guid.NewGuid(),
                DueDate = new DateOnly(2026, 10, 1),
                Amount = 85000m,
                Status = RentScheduleStatus.Pending,
                CreatedAt = DateTimeOffset.UtcNow
            }
        };

        var rentScheduleService = new StubRentScheduleService
        {
            GetByTenantResult = expectedItems
        };

        var currentUserService = new StubCurrentUserService
        {
            UserIdValue = tenantId
        };

        var controller = new RentSchedulesController(
            rentScheduleService,
            currentUserService);

        var result = await controller.GetMine(
            CancellationToken.None);

        var okResult = Assert.IsType<OkObjectResult>(result);

        Assert.Equal(expectedItems, okResult.Value);
        Assert.Equal(tenantId, rentScheduleService.LastTenantId);
    }

    [Fact]
    public async Task GetByLease_WhenSuccessful_ReturnsOk()
    {
        var leaseAgreementId = Guid.NewGuid();

        var expectedItems = new List<RentScheduleItemResponseDto>
        {
            new()
            {
                Id = Guid.NewGuid(),
                LeaseAgreementId = leaseAgreementId,
                DueDate = new DateOnly(2026, 10, 1),
                Amount = 85000m,
                Status = RentScheduleStatus.Pending,
                CreatedAt = DateTimeOffset.UtcNow
            },
            new()
            {
                Id = Guid.NewGuid(),
                LeaseAgreementId = leaseAgreementId,
                DueDate = new DateOnly(2026, 11, 1),
                Amount = 85000m,
                Status = RentScheduleStatus.Pending,
                CreatedAt = DateTimeOffset.UtcNow
            }
        };

        var rentScheduleService = new StubRentScheduleService
        {
            GetByLeaseResult = expectedItems
        };

        var currentUserService = new StubCurrentUserService();

        var controller = new RentSchedulesController(
            rentScheduleService,
            currentUserService);

        var result = await controller.GetByLease(
            leaseAgreementId,
            CancellationToken.None);

        var okResult = Assert.IsType<OkObjectResult>(result);

        Assert.Equal(expectedItems, okResult.Value);
    }

    [Fact]
    public async Task GetById_WhenItemExists_ReturnsOk()
    {
        var expectedItem = new RentScheduleItemResponseDto
        {
            Id = Guid.NewGuid(),
            LeaseAgreementId = Guid.NewGuid(),
            DueDate = new DateOnly(2026, 10, 1),
            Amount = 85000m,
            Status = RentScheduleStatus.Pending,
            CreatedAt = DateTimeOffset.UtcNow
        };

        var rentScheduleService = new StubRentScheduleService
        {
            GetByIdResult = expectedItem
        };

        var currentUserService = new StubCurrentUserService();

        var controller = new RentSchedulesController(
            rentScheduleService,
            currentUserService);

        var result = await controller.GetById(
            expectedItem.Id,
            CancellationToken.None);

        var okResult = Assert.IsType<OkObjectResult>(result);

        Assert.Equal(expectedItem, okResult.Value);
    }

    [Fact]
    public async Task GetById_WhenItemDoesNotExist_ReturnsNotFound()
    {
        var rentScheduleService = new StubRentScheduleService
        {
            GetByIdResult = null
        };

        var currentUserService = new StubCurrentUserService();

        var controller = new RentSchedulesController(
            rentScheduleService,
            currentUserService);

        var result = await controller.GetById(
            Guid.NewGuid(),
            CancellationToken.None);

        Assert.IsType<NotFoundObjectResult>(result);
    }

    private sealed class StubRentScheduleService : IRentScheduleService
    {
        public Task<bool> CanAccessLeaseAsync(
            Guid leaseAgreementId,
            Guid? userId,
            UserRole? role,
            CancellationToken cancellationToken = default)
        {
            return Task.FromResult(true);
        }

        public Task<bool> CanAccessScheduleItemAsync(
            Guid scheduleItemId,
            Guid? userId,
            UserRole? role,
            CancellationToken cancellationToken = default)
        {
            return Task.FromResult(true);
        }

        public IReadOnlyList<RentScheduleItemResponseDto>? GenerateResult { get; set; }

        public IReadOnlyList<RentScheduleItemResponseDto>? GetByTenantResult { get; set; }

        public IReadOnlyList<RentScheduleItemResponseDto>? GetByLeaseResult { get; set; }

        public RentScheduleItemResponseDto? GetByIdResult { get; set; }

        public Guid? LastTenantId { get; private set; }

        public Task<IReadOnlyList<RentScheduleItemResponseDto>> GenerateForLeaseAsync(
            Guid leaseAgreementId,
            CancellationToken cancellationToken = default)
        {
            return Task.FromResult(
                GenerateResult ?? Array.Empty<RentScheduleItemResponseDto>());
        }

        public Task<IReadOnlyList<RentScheduleItemResponseDto>> GetByLeaseAsync(
            Guid leaseAgreementId,
            CancellationToken cancellationToken = default)
        {
            return Task.FromResult(
                GetByLeaseResult ?? Array.Empty<RentScheduleItemResponseDto>());
        }

        public Task<IReadOnlyList<RentScheduleItemResponseDto>> GetByTenantAsync(
            Guid tenantId,
            CancellationToken cancellationToken = default)
        {
            LastTenantId = tenantId;

            return Task.FromResult(
                GetByTenantResult ?? Array.Empty<RentScheduleItemResponseDto>());
        }

        public Task<RentScheduleItemResponseDto?> GetByIdAsync(
            Guid id,
            CancellationToken cancellationToken = default)
        {
            return Task.FromResult(GetByIdResult);
        }
    }

    private sealed class StubCurrentUserService : ICurrentUserService
    {
        public bool IsAuthenticated => true;

        public Guid? UserIdValue { get; set; } = Guid.NewGuid();

        public Guid? UserId => UserIdValue;

        public UserRole? Role => UserRole.Tenant;
    }
}
