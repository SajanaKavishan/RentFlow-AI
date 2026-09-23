using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using RentFlow.Api.Services;
using RentFlow.Api.Services.Interfaces;

namespace RentFlow.Api.Controllers;

[ApiController]
[Route("api/rent-schedules")]
[Authorize]
public class RentSchedulesController : ControllerBase
{
    private readonly IRentScheduleService _rentScheduleService;
    private readonly ICurrentUserService _currentUserService;

    public RentSchedulesController(
        IRentScheduleService rentScheduleService,
        ICurrentUserService currentUserService)
    {
        _rentScheduleService = rentScheduleService;
        _currentUserService = currentUserService;
    }

    [HttpPost("lease/{leaseAgreementId:guid}/generate")]
    [Authorize(Roles = "Landlord,Admin")]
    public async Task<IActionResult> GenerateForLease(
        Guid leaseAgreementId,
        CancellationToken cancellationToken)
    {
        return await ExecuteAsync(async () =>
        {
            if (!await _rentScheduleService.CanAccessLeaseAsync(
                    leaseAgreementId,
                    _currentUserService.UserId,
                    _currentUserService.Role,
                    cancellationToken))
            {
                return NotFound(new
                {
                    message = "Lease agreement was not found."
                });
            }

            var scheduleItems = await _rentScheduleService.GenerateForLeaseAsync(
                leaseAgreementId,
                cancellationToken);

            return Ok(scheduleItems);
        });
    }

    [HttpGet("lease/{leaseAgreementId:guid}")]
    [Authorize(Roles = "Tenant,Landlord,Admin")]
    public async Task<IActionResult> GetByLease(
        Guid leaseAgreementId,
        CancellationToken cancellationToken)
    {
        return await ExecuteAsync(async () =>
        {
            if (!await _rentScheduleService.CanAccessLeaseAsync(
                    leaseAgreementId,
                    _currentUserService.UserId,
                    _currentUserService.Role,
                    cancellationToken))
            {
                return NotFound(new
                {
                    message = "Lease agreement was not found."
                });
            }

            var scheduleItems = await _rentScheduleService.GetByLeaseAsync(
                leaseAgreementId,
                cancellationToken);

            return Ok(scheduleItems);
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

            var scheduleItems = await _rentScheduleService.GetByTenantAsync(
                tenantId.Value,
                cancellationToken);

            return Ok(scheduleItems);
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
            if (!await _rentScheduleService.CanAccessScheduleItemAsync(
                    id,
                    _currentUserService.UserId,
                    _currentUserService.Role,
                    cancellationToken))
            {
                return NotFound(new
                {
                    message = "Rent schedule item was not found."
                });
            }

            var scheduleItem = await _rentScheduleService.GetByIdAsync(
                id,
                cancellationToken);

            if (scheduleItem is null)
            {
                return NotFound(new
                {
                    message = "Rent schedule item was not found."
                });
            }

            return Ok(scheduleItem);
        });
    }

    private async Task<IActionResult> ExecuteAsync(
        Func<Task<IActionResult>> action)
    {
        try
        {
            return await action();
        }
        catch (RentScheduleServiceException ex)
        {
            return ex.Error switch
            {
                RentScheduleServiceError.Validation =>
                    BadRequest(new { message = ex.Message }),

                RentScheduleServiceError.NotFound =>
                    NotFound(new { message = ex.Message }),

                RentScheduleServiceError.Conflict =>
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
