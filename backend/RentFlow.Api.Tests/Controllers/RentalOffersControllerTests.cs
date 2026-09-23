using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Logging.Abstractions;
using RentFlow.Api.Controllers;
using RentFlow.Api.DTOs.RentalOffers;
using RentFlow.Api.Models;
using RentFlow.Api.Services;
using RentFlow.Api.Services.Interfaces;
using Xunit;

namespace RentFlow.Api.Tests.Controllers;

public class RentalOffersControllerTests
{
    [Fact]
    public async Task Create_ReturnsCreatedRentalOffer()
    {
        var offer = CreateOfferResponse();

        var service = new StubRentalOfferService
        {
            CreateHandler = (_, _) => Task.FromResult(offer)
        };

        var controller = CreateController(
            service,
            new StubCurrentUserService());

        var request = new CreateRentalOfferDto
        {
            RentalApplicationId = offer.RentalApplicationId,
            MonthlyRent = offer.MonthlyRent,
            SecurityDeposit = offer.SecurityDeposit,
            ProposedStartDate = offer.ProposedStartDate,
            ProposedEndDate = offer.ProposedEndDate,
            ExpiresAt = offer.ExpiresAt,
            LandlordNote = offer.LandlordNote
        };

        var response = await controller.Create(
            request,
            CancellationToken.None);

        var created = Assert.IsType<CreatedAtActionResult>(response.Result);

        Assert.Equal(StatusCodes.Status201Created, created.StatusCode);
        Assert.Equal(nameof(RentalOffersController.GetById), created.ActionName);
        Assert.Equal(offer.Id, created.RouteValues!["id"]);
        Assert.Same(offer, created.Value);
    }

    [Fact]
    public async Task GetById_ReturnsOffer_WhenOfferExists()
    {
        var offer = CreateOfferResponse();

        var service = new StubRentalOfferService
        {
            GetByIdHandler = (_, _) =>
                Task.FromResult<RentalOfferResponseDto?>(offer)
        };

        var controller = CreateController(
            service,
            new StubCurrentUserService { UserId = offer.TenantId });

        var response = await controller.GetById(
            offer.Id,
            CancellationToken.None);

        var ok = Assert.IsType<OkObjectResult>(response.Result);

        Assert.Equal(StatusCodes.Status200OK, ok.StatusCode);
        Assert.Same(offer, ok.Value);
    }

    [Fact]
    public async Task GetById_ReturnsNotFound_WhenOfferDoesNotExist()
    {
        var service = new StubRentalOfferService
        {
            GetByIdHandler = (_, _) =>
                Task.FromResult<RentalOfferResponseDto?>(null)
        };

        var controller = CreateController(
            service,
            new StubCurrentUserService());

        var response = await controller.GetById(
            Guid.NewGuid(),
            CancellationToken.None);

        var result = Assert.IsType<ObjectResult>(response.Result);

        Assert.Equal(StatusCodes.Status404NotFound, result.StatusCode);

        var problem = Assert.IsType<ProblemDetails>(result.Value);

        Assert.Equal("Rental offer not found.", problem.Title);
    }

    [Fact]
    public async Task GetMine_UsesAuthenticatedTenantId()
    {
        var tenantId = Guid.NewGuid();

        var offers = new List<RentalOfferResponseDto>
        {
            CreateOfferResponse(tenantId)
        };

        var service = new StubRentalOfferService
        {
            GetByTenantHandler = (_, _) =>
                Task.FromResult<IReadOnlyList<RentalOfferResponseDto>>(offers)
        };

        var currentUser = new StubCurrentUserService
        {
            UserId = tenantId,
            Role = UserRole.Tenant
        };

        var controller = CreateController(
            service,
            currentUser);

        var response = await controller.GetMine(
            CancellationToken.None);

        var ok = Assert.IsType<OkObjectResult>(response.Result);

        Assert.Equal(StatusCodes.Status200OK, ok.StatusCode);
        Assert.Same(offers, ok.Value);
        Assert.Equal(tenantId, service.RequestedTenantId);
    }

    [Fact]
    public async Task Accept_UsesAuthenticatedTenantId()
    {
        var tenantId = Guid.NewGuid();

        var offer = CreateOfferResponse(tenantId);
        offer.Status = RentalOfferStatus.Accepted;

        var service = new StubRentalOfferService
        {
            AcceptHandler = (_, _, _) =>
                Task.FromResult(offer)
        };

        var currentUser = new StubCurrentUserService
        {
            UserId = tenantId,
            Role = UserRole.Tenant
        };

        var controller = CreateController(
            service,
            currentUser);

        var response = await controller.Accept(
            offer.Id,
            CancellationToken.None);

        var ok = Assert.IsType<OkObjectResult>(response.Result);

        Assert.Equal(StatusCodes.Status200OK, ok.StatusCode);
        Assert.Same(offer, ok.Value);
        Assert.Equal(offer.Id, service.RequestedOfferId);
        Assert.Equal(tenantId, service.RequestedTenantId);
    }

    [Fact]
    public async Task Withdraw_MapsServiceConflictToConflictResponse()
    {
        var service = new StubRentalOfferService
        {
            WithdrawHandler = (_, _) =>
                throw RentalOfferServiceException.Conflict(
                    "Only pending rental offers can be withdrawn.")
        };

        var controller = CreateController(
            service,
            new StubCurrentUserService());

        var response = await controller.Withdraw(
            Guid.NewGuid(),
            CancellationToken.None);

        var result = Assert.IsType<ObjectResult>(response.Result);

        Assert.Equal(StatusCodes.Status409Conflict, result.StatusCode);

        var problem = Assert.IsType<ProblemDetails>(result.Value);

        Assert.Equal("Rental offer conflict.", problem.Title);
        Assert.Equal(
            "Only pending rental offers can be withdrawn.",
            problem.Detail);
    }

    private static RentalOffersController CreateController(
        IRentalOfferService rentalOfferService,
        ICurrentUserService currentUser)
    {
        return new RentalOffersController(
            rentalOfferService,
            currentUser,
            new StubPropertyAccessGuard(),
            NullLogger<RentalOffersController>.Instance)
        {
            ControllerContext = new ControllerContext
            {
                HttpContext = new DefaultHttpContext()
            }
        };
    }

    private static RentalOfferResponseDto CreateOfferResponse(
        Guid? tenantId = null)
    {
        return new RentalOfferResponseDto
        {
            Id = Guid.NewGuid(),
            RentalApplicationId = Guid.NewGuid(),
            TenantId = tenantId ?? Guid.NewGuid(),
            PropertyId = Guid.NewGuid(),
            MonthlyRent = 85000m,
            SecurityDeposit = 170000m,
            ProposedStartDate = DateOnly.FromDateTime(
                DateTime.UtcNow.AddDays(30)),
            ProposedEndDate = DateOnly.FromDateTime(
                DateTime.UtcNow.AddMonths(12)),
            ExpiresAt = DateTimeOffset.UtcNow.AddDays(7),
            Status = RentalOfferStatus.Pending,
            LandlordNote = "Rental offer test.",
            CreatedAt = DateTimeOffset.UtcNow
        };
    }

    private sealed class StubCurrentUserService : ICurrentUserService
    {
        public bool IsAuthenticated { get; init; } = true;

        public Guid? UserId { get; init; } = Guid.NewGuid();

        public UserRole? Role { get; init; } = UserRole.Tenant;
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
    }

    private sealed class StubRentalOfferService : IRentalOfferService
    {
        public Func<CreateRentalOfferDto, CancellationToken,
            Task<RentalOfferResponseDto>>? CreateHandler { get; init; }

        public Func<Guid, CancellationToken,
            Task<RentalOfferResponseDto?>>? GetByIdHandler { get; init; }

        public Func<Guid, CancellationToken,
            Task<IReadOnlyList<RentalOfferResponseDto>>>?
            GetByTenantHandler { get; init; }

        public Func<Guid, Guid, CancellationToken,
            Task<RentalOfferResponseDto>>? AcceptHandler { get; init; }

        public Func<Guid, Guid, CancellationToken,
            Task<RentalOfferResponseDto>>? RejectHandler { get; init; }

        public Func<Guid, CancellationToken,
            Task<RentalOfferResponseDto>>? WithdrawHandler { get; init; }

        public Guid? RequestedTenantId { get; private set; }

        public Guid? RequestedOfferId { get; private set; }

        public Task<RentalOfferResponseDto> CreateAsync(
            CreateRentalOfferDto dto,
            CancellationToken cancellationToken = default)
        {
            return CreateHandler?.Invoke(dto, cancellationToken)
                ?? Task.FromResult(CreateOfferResponse());
        }

        public Task<RentalOfferResponseDto?> GetByIdAsync(
            Guid id,
            CancellationToken cancellationToken = default)
        {
            return GetByIdHandler?.Invoke(id, cancellationToken)
                ?? Task.FromResult<RentalOfferResponseDto?>(null);
        }

        public Task<RentalOfferResponseDto?> RefreshExpiredByIdAsync(
            Guid id,
            CancellationToken cancellationToken = default)
        {
            return GetByIdHandler?.Invoke(id, cancellationToken)
                ?? Task.FromResult<RentalOfferResponseDto?>(null);
        }

        public Task<IReadOnlyList<RentalOfferResponseDto>> GetByTenantAsync(
            Guid tenantId,
            CancellationToken cancellationToken = default)
        {
            RequestedTenantId = tenantId;

            return GetByTenantHandler?.Invoke(
                    tenantId,
                    cancellationToken)
                ?? Task.FromResult<IReadOnlyList<RentalOfferResponseDto>>(
                    Array.Empty<RentalOfferResponseDto>());
        }

        public Task<RentalOfferResponseDto> AcceptAsync(
            Guid offerId,
            Guid tenantId,
            CancellationToken cancellationToken = default)
        {
            RequestedOfferId = offerId;
            RequestedTenantId = tenantId;

            return AcceptHandler?.Invoke(
                    offerId,
                    tenantId,
                    cancellationToken)
                ?? Task.FromResult(CreateOfferResponse(tenantId));
        }

        public Task<RentalOfferResponseDto> RejectAsync(
            Guid offerId,
            Guid tenantId,
            CancellationToken cancellationToken = default)
        {
            RequestedOfferId = offerId;
            RequestedTenantId = tenantId;

            return RejectHandler?.Invoke(
                    offerId,
                    tenantId,
                    cancellationToken)
                ?? Task.FromResult(CreateOfferResponse(tenantId));
        }

        public Task<RentalOfferResponseDto> WithdrawAsync(
            Guid offerId,
            CancellationToken cancellationToken = default)
        {
            RequestedOfferId = offerId;

            return WithdrawHandler?.Invoke(
                    offerId,
                    cancellationToken)
                ?? Task.FromResult(CreateOfferResponse());
        }
    }
}
