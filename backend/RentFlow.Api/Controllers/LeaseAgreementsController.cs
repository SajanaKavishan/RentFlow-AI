using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using RentFlow.Api.DTOs.LeaseAgreements;
using RentFlow.Api.Models;
using RentFlow.Api.Services;
using RentFlow.Api.Services.Interfaces;

namespace RentFlow.Api.Controllers;

[ApiController]
[Route("api/lease-agreements")]
[Authorize]
public class LeaseAgreementsController : ControllerBase
{
    private readonly ILeaseAgreementService _leaseAgreementService;
    private readonly ICurrentUserService _currentUserService;
    private readonly IPropertyAccessGuard _propertyAccessGuard;

    public LeaseAgreementsController(
        ILeaseAgreementService leaseAgreementService,
        ICurrentUserService currentUserService,
        IPropertyAccessGuard propertyAccessGuard)
    {
        _leaseAgreementService = leaseAgreementService;
        _currentUserService = currentUserService;
        _propertyAccessGuard = propertyAccessGuard;
    }

    [HttpPost]
    [Authorize(Roles = "Landlord,Admin")]
    public async Task<IActionResult> Create(
        [FromBody] CreateLeaseAgreementDto dto,
        CancellationToken cancellationToken)
    {
        return await ExecuteAsync(async () =>
        {
            if (_currentUserService.Role == UserRole.Landlord
                && !await _propertyAccessGuard.CanAccessRentalOfferAsync(
                    GetRequiredUserId(),
                    dto.RentalOfferId,
                    cancellationToken))
            {
                throw LeaseAgreementServiceException.NotFound(
                    "Rental offer was not found.");
            }

            var lease = await _leaseAgreementService.CreateAsync(
                dto,
                cancellationToken);

            return CreatedAtAction(
                nameof(GetById),
                new { id = lease.Id },
                lease);
        });
    }

    [HttpGet("mine")]
    [Authorize(Roles = "Tenant")]
    public async Task<IActionResult> GetMine(
        CancellationToken cancellationToken)
    {
        return await ExecuteAsync(async () =>
        {
            var tenantId = _currentUserService.UserId;

            if (tenantId is null)
            {
                return Unauthorized(new
                {
                    message = "Authenticated user ID was not found."
                });
            }

            var leases = await _leaseAgreementService.GetByTenantAsync(
                tenantId.Value,
                cancellationToken);

            return Ok(leases);
        });
    }

    [HttpGet("{id:guid}")]
    [Authorize(Roles = "Tenant,Landlord,Admin")]
    public async Task<IActionResult> GetById(
        Guid id,
        CancellationToken cancellationToken)
    {
        return await ExecuteAsync(async () =>
        {
            var lease = await _leaseAgreementService.GetByIdAsync(
                id,
                cancellationToken);

            if (lease is null
                || _currentUserService.Role == UserRole.Tenant
                    && lease.TenantId != _currentUserService.UserId
                || _currentUserService.Role == UserRole.Landlord
                    && (_currentUserService.UserId is not Guid landlordId
                        || !await _propertyAccessGuard.CanAccessPropertyAsync(
                            landlordId, lease.PropertyId, cancellationToken)))
            {
                return NotFound(new
                {
                    message = "Lease agreement was not found."
                });
            }

            return Ok(lease);
        });
    }

    [HttpPatch("{id:guid}/activate")]
    [Authorize(Roles = "Landlord,Admin")]
    public async Task<IActionResult> Activate(
        Guid id,
        CancellationToken cancellationToken)
    {
        return await ExecuteAsync(async () =>
        {
            await EnsureLandlordCanAccessLeaseAsync(id, cancellationToken);

            var lease = await _leaseAgreementService.ActivateAsync(
                id,
                cancellationToken);

            return Ok(lease);
        });
    }

    [HttpPatch("{id:guid}/terminate")]
    [Authorize(Roles = "Landlord,Admin")]
    public async Task<IActionResult> Terminate(
        Guid id,
        CancellationToken cancellationToken)
    {
        return await ExecuteAsync(async () =>
        {
            await EnsureLandlordCanAccessLeaseAsync(id, cancellationToken);

            var lease = await _leaseAgreementService.TerminateAsync(
                id,
                cancellationToken);

            return Ok(lease);
        });
    }

    [HttpPatch("{id:guid}/complete")]
    [Authorize(Roles = "Landlord,Admin")]
    public async Task<IActionResult> Complete(
        Guid id,
        CancellationToken cancellationToken)
    {
        return await ExecuteAsync(async () =>
        {
            await EnsureLandlordCanAccessLeaseAsync(id, cancellationToken);

            var lease = await _leaseAgreementService.CompleteAsync(
                id,
                cancellationToken);

            return Ok(lease);
        });
    }

    private async Task EnsureLandlordCanAccessLeaseAsync(
        Guid leaseId,
        CancellationToken cancellationToken)
    {
        if (_currentUserService.Role != UserRole.Landlord)
        {
            return;
        }

        var lease = await _leaseAgreementService.GetByIdAsync(
            leaseId,
            cancellationToken);

        if (lease is null
            || _currentUserService.UserId is not Guid landlordId
            || !await _propertyAccessGuard.CanAccessPropertyAsync(
                landlordId, lease.PropertyId, cancellationToken))
        {
            throw LeaseAgreementServiceException.NotFound(
                "Lease agreement was not found.");
        }
    }

    private Guid GetRequiredUserId() => _currentUserService.UserId
        ?? throw new InvalidOperationException(
            "The authenticated JWT has no valid user ID.");

    private async Task<IActionResult> ExecuteAsync(
        Func<Task<IActionResult>> action)
    {
        try
        {
            return await action();
        }
        catch (LeaseAgreementServiceException ex)
        {
            return ex.Error switch
            {
                LeaseAgreementServiceError.Validation =>
                    BadRequest(new { message = ex.Message }),

                LeaseAgreementServiceError.NotFound =>
                    NotFound(new { message = ex.Message }),

                LeaseAgreementServiceError.Conflict =>
                    Conflict(new { message = ex.Message }),

                _ =>
                    StatusCode(
                        StatusCodes.Status500InternalServerError,
                        new { message = "An unexpected error occurred." })
            };
        }
        catch
        {
            return StatusCode(
                StatusCodes.Status500InternalServerError,
                new { message = "An unexpected error occurred." });
        }
    }
}
