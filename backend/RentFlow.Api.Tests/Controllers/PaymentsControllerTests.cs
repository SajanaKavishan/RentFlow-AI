using Microsoft.AspNetCore.Mvc;
using RentFlow.Api.Controllers;
using RentFlow.Api.DTOs.Payments;
using RentFlow.Api.DTOs.RentSchedules;
using RentFlow.Api.Models;
using RentFlow.Api.Services;
using RentFlow.Api.Services.Interfaces;
using Xunit;

namespace RentFlow.Api.Tests.Controllers;

public class PaymentsControllerTests
{
    [Fact]
    public async Task Create_WhenSuccessful_ReturnsCreatedAtAction()
    {
        var tenantId = Guid.NewGuid();

        var expectedPayment = new PaymentResponseDto
        {
            Id = Guid.NewGuid(),
            RentScheduleItemId = Guid.NewGuid(),
            TenantId = tenantId,
            Amount = 85000m,
            PaymentMethod = "BankTransfer",
            TransactionReference = "TXN-001",
            Status = PaymentStatus.Pending,
            CreatedAt = DateTimeOffset.UtcNow
        };

        var paymentService = new StubPaymentService
        {
            CreateResult = expectedPayment
        };

        var currentUserService = new StubCurrentUserService
        {
            UserIdValue = tenantId
        };

        var controller = CreateController(paymentService, currentUserService);

        var dto = new CreatePaymentDto
        {
            RentScheduleItemId = expectedPayment.RentScheduleItemId,
            PaymentMethod = "BankTransfer",
            TransactionReference = "TXN-001"
        };

        var result = await controller.Create(
            dto,
            CancellationToken.None);

        var createdResult = Assert.IsType<CreatedAtActionResult>(result);

        Assert.Equal(
            nameof(PaymentsController.GetById),
            createdResult.ActionName);

        Assert.Equal(expectedPayment, createdResult.Value);
        Assert.Equal(tenantId, paymentService.LastTenantId);
    }

    [Fact]
    public async Task GetMine_UsesAuthenticatedTenantId()
    {
        var tenantId = Guid.NewGuid();

        var expectedPayments = new List<PaymentResponseDto>
        {
            new()
            {
                Id = Guid.NewGuid(),
                RentScheduleItemId = Guid.NewGuid(),
                TenantId = tenantId,
                Amount = 85000m,
                PaymentMethod = "BankTransfer",
                TransactionReference = "TXN-002",
                Status = PaymentStatus.Completed,
                PaidAt = DateTimeOffset.UtcNow,
                CreatedAt = DateTimeOffset.UtcNow
            }
        };

        var paymentService = new StubPaymentService
        {
            GetByTenantResult = expectedPayments
        };

        var currentUserService = new StubCurrentUserService
        {
            UserIdValue = tenantId
        };

        var controller = CreateController(paymentService, currentUserService);

        var result = await controller.GetMine(
            CancellationToken.None);

        var okResult = Assert.IsType<OkObjectResult>(result);

        Assert.Equal(expectedPayments, okResult.Value);
        Assert.Equal(tenantId, paymentService.LastTenantId);
    }

    [Fact]
    public async Task GetById_WhenPaymentExists_ReturnsOk()
    {
        var expectedPayment = new PaymentResponseDto
        {
            Id = Guid.NewGuid(),
            RentScheduleItemId = Guid.NewGuid(),
            TenantId = Guid.NewGuid(),
            Amount = 85000m,
            PaymentMethod = "BankTransfer",
            TransactionReference = "TXN-003",
            Status = PaymentStatus.Pending,
            CreatedAt = DateTimeOffset.UtcNow
        };

        var paymentService = new StubPaymentService
        {
            GetByIdResult = expectedPayment
        };

        var currentUserService = new StubCurrentUserService();

        var controller = CreateController(paymentService, currentUserService);

        var result = await controller.GetById(
            expectedPayment.Id,
            CancellationToken.None);

        var okResult = Assert.IsType<OkObjectResult>(result);

        Assert.Equal(expectedPayment, okResult.Value);
    }

    [Fact]
    public async Task GetById_WhenPaymentDoesNotExist_ReturnsNotFound()
    {
        var paymentService = new StubPaymentService
        {
            GetByIdResult = null
        };

        var currentUserService = new StubCurrentUserService();

        var controller = CreateController(paymentService, currentUserService);

        var result = await controller.GetById(
            Guid.NewGuid(),
            CancellationToken.None);

        Assert.IsType<NotFoundObjectResult>(result);
    }

    [Fact]
    public async Task Complete_WhenSuccessful_ReturnsOk()
    {
        var expectedPayment = new PaymentResponseDto
        {
            Id = Guid.NewGuid(),
            RentScheduleItemId = Guid.NewGuid(),
            TenantId = Guid.NewGuid(),
            Amount = 85000m,
            PaymentMethod = "BankTransfer",
            TransactionReference = "TXN-004",
            Status = PaymentStatus.Completed,
            PaidAt = DateTimeOffset.UtcNow,
            CreatedAt = DateTimeOffset.UtcNow,
            UpdatedAt = DateTimeOffset.UtcNow
        };

        var paymentService = new StubPaymentService
        {
            GetByIdResult = expectedPayment,
            CompleteResult = expectedPayment
        };

        var currentUserService = new StubCurrentUserService();

        var controller = CreateController(paymentService, currentUserService);

        var result = await controller.Complete(
            expectedPayment.Id,
            CancellationToken.None);

        var okResult = Assert.IsType<OkObjectResult>(result);

        Assert.Equal(expectedPayment, okResult.Value);
    }

    [Fact]
    public async Task Fail_WhenSuccessful_ReturnsOk()
    {
        var expectedPayment = new PaymentResponseDto
        {
            Id = Guid.NewGuid(),
            RentScheduleItemId = Guid.NewGuid(),
            TenantId = Guid.NewGuid(),
            Amount = 85000m,
            PaymentMethod = "BankTransfer",
            TransactionReference = "TXN-005",
            Status = PaymentStatus.Failed,
            CreatedAt = DateTimeOffset.UtcNow,
            UpdatedAt = DateTimeOffset.UtcNow
        };

        var paymentService = new StubPaymentService
        {
            GetByIdResult = expectedPayment,
            FailResult = expectedPayment
        };

        var currentUserService = new StubCurrentUserService();

        var controller = CreateController(paymentService, currentUserService);

        var result = await controller.Fail(
            expectedPayment.Id,
            CancellationToken.None);

        var okResult = Assert.IsType<OkObjectResult>(result);

        Assert.Equal(expectedPayment, okResult.Value);
    }

    private static PaymentsController CreateController(
        IPaymentService paymentService,
        ICurrentUserService currentUserService)
    {
        return new PaymentsController(
            paymentService,
            currentUserService,
            new StubRentScheduleService());
    }

    private sealed class StubPaymentService : IPaymentService
    {
        public PaymentResponseDto? CreateResult { get; set; }

        public PaymentResponseDto? GetByIdResult { get; set; }

        public IReadOnlyList<PaymentResponseDto>? GetByTenantResult { get; set; }

        public IReadOnlyList<PaymentResponseDto>? GetByLandlordResult { get; set; }

        public PaymentResponseDto? CompleteResult { get; set; }

        public PaymentResponseDto? FailResult { get; set; }

        public Guid? LastTenantId { get; private set; }

        public Task<PaymentResponseDto> CreateAsync(
            CreatePaymentDto dto,
            Guid tenantId,
            CancellationToken cancellationToken = default)
        {
            LastTenantId = tenantId;

            return Task.FromResult(CreateResult!);
        }

        public Task<PaymentResponseDto?> GetByIdAsync(
            Guid id,
            CancellationToken cancellationToken = default)
        {
            return Task.FromResult(GetByIdResult);
        }

        public Task<IReadOnlyList<PaymentResponseDto>> GetByTenantAsync(
            Guid tenantId,
            CancellationToken cancellationToken = default)
        {
            LastTenantId = tenantId;

            return Task.FromResult(
                GetByTenantResult ?? Array.Empty<PaymentResponseDto>());
        }

        public Task<IReadOnlyList<PaymentResponseDto>> GetByLandlordAsync(
            Guid landlordId,
            CancellationToken cancellationToken = default)
        {
            LastTenantId = landlordId;

            return Task.FromResult(
                GetByLandlordResult ?? Array.Empty<PaymentResponseDto>());
        }

        public Task<PaymentResponseDto> CompleteAsync(
            Guid paymentId,
            CancellationToken cancellationToken = default)
        {
            return Task.FromResult(CompleteResult!);
        }

        public Task<PaymentResponseDto> FailAsync(
            Guid paymentId,
            CancellationToken cancellationToken = default)
        {
            return Task.FromResult(FailResult!);
        }
    }

    private sealed class StubRentScheduleService : IRentScheduleService
    {
        public Task<bool> CanAccessLeaseAsync(
            Guid leaseAgreementId,
            Guid? userId,
            UserRole? role,
            CancellationToken cancellationToken = default)
            => Task.FromResult(true);

        public Task<bool> CanAccessScheduleItemAsync(
            Guid scheduleItemId,
            Guid? userId,
            UserRole? role,
            CancellationToken cancellationToken = default)
            => Task.FromResult(true);

        public Task<IReadOnlyList<RentScheduleItemResponseDto>> GenerateForLeaseAsync(
            Guid leaseAgreementId,
            CancellationToken cancellationToken = default)
            => Task.FromResult<IReadOnlyList<RentScheduleItemResponseDto>>(
                Array.Empty<RentScheduleItemResponseDto>());

        public Task<IReadOnlyList<RentScheduleItemResponseDto>> GetByLeaseAsync(
            Guid leaseAgreementId,
            CancellationToken cancellationToken = default)
            => Task.FromResult<IReadOnlyList<RentScheduleItemResponseDto>>(
                Array.Empty<RentScheduleItemResponseDto>());

        public Task<IReadOnlyList<RentScheduleItemResponseDto>> GetByTenantAsync(
            Guid tenantId,
            CancellationToken cancellationToken = default)
            => Task.FromResult<IReadOnlyList<RentScheduleItemResponseDto>>(
                Array.Empty<RentScheduleItemResponseDto>());

        public Task<RentScheduleOutstandingSummaryDto> GetOutstandingByLeaseAsync(
            Guid leaseAgreementId,
            CancellationToken cancellationToken = default)
            => Task.FromResult(new RentScheduleOutstandingSummaryDto());

        public Task<RentScheduleOutstandingSummaryDto> GetOutstandingByTenantAsync(
            Guid tenantId,
            CancellationToken cancellationToken = default)
            => Task.FromResult(new RentScheduleOutstandingSummaryDto());

        public Task<RentScheduleItemResponseDto?> GetByIdAsync(
            Guid id,
            CancellationToken cancellationToken = default)
            => Task.FromResult<RentScheduleItemResponseDto?>(null);
    }

    private sealed class StubCurrentUserService : ICurrentUserService
    {
        public bool IsAuthenticated => true;

        public Guid? UserIdValue { get; set; } = Guid.NewGuid();

        public Guid? UserId => UserIdValue;

        public UserRole? Role => UserRole.Tenant;
    }
}
