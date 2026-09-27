using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using RentFlow.Api.DTOs.Payments;
using RentFlow.Api.Services;
using RentFlow.Api.Services.Interfaces;

namespace RentFlow.Api.Controllers;

[ApiController]
[Route("api/payments")]
[Authorize]
public class PaymentsController : ControllerBase
{
    private readonly IPaymentService _paymentService;
    private readonly ICurrentUserService _currentUserService;
    private readonly IRentScheduleService _rentScheduleService;

    public PaymentsController(
        IPaymentService paymentService,
        ICurrentUserService currentUserService,
        IRentScheduleService rentScheduleService)
    {
        _paymentService = paymentService;
        _currentUserService = currentUserService;
        _rentScheduleService = rentScheduleService;
    }

    [HttpPost]
    [Authorize(Roles = "Tenant")]
    public async Task<IActionResult> Create(
        [FromBody] CreatePaymentDto dto,
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

            var payment = await _paymentService.CreateAsync(
                dto,
                tenantId.Value,
                cancellationToken);

            return CreatedAtAction(
                nameof(GetById),
                new { id = payment.Id },
                payment);
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

            var payments = await _paymentService.GetByTenantAsync(
                tenantId.Value,
                cancellationToken);

            return Ok(payments);
        });
    }

    [HttpGet("landlord")]
    [Authorize(Roles = "Landlord")]
    public async Task<IActionResult> GetByLandlord(
        CancellationToken cancellationToken)
    {
        return await ExecuteAsync(async () =>
        {
            var landlordId = _currentUserService.UserId;
            if (landlordId is null)
            {
                return Unauthorized(new
                {
                    message = "Authenticated user ID was not found."
                });
            }

            var payments = await _paymentService.GetByLandlordAsync(
                landlordId.Value,
                cancellationToken);

            return Ok(payments);
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
            var payment = await _paymentService.GetByIdAsync(
                id,
                cancellationToken);

            if (payment is null)
            {
                return NotFound(new
                {
                    message = "Payment was not found."
                });
            }

            if (!await _rentScheduleService.CanAccessScheduleItemAsync(
                    payment.RentScheduleItemId,
                    _currentUserService.UserId,
                    _currentUserService.Role,
                    cancellationToken))
            {
                return NotFound(new
                {
                    message = "Payment was not found."
                });
            }

            return Ok(payment);
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
            if (!await CanAccessPaymentAsync(id, cancellationToken))
            {
                return NotFound(new
                {
                    message = "Payment was not found."
                });
            }

            var payment = await _paymentService.CompleteAsync(
                id,
                cancellationToken);

            return Ok(payment);
        });
    }

    [HttpPatch("{id:guid}/fail")]
    [Authorize(Roles = "Landlord,Admin")]
    public async Task<IActionResult> Fail(
        Guid id,
        CancellationToken cancellationToken)
    {
        return await ExecuteAsync(async () =>
        {
            if (!await CanAccessPaymentAsync(id, cancellationToken))
            {
                return NotFound(new
                {
                    message = "Payment was not found."
                });
            }

            var payment = await _paymentService.FailAsync(
                id,
                cancellationToken);

            return Ok(payment);
        });
    }

    private async Task<bool> CanAccessPaymentAsync(
        Guid paymentId,
        CancellationToken cancellationToken)
    {
        var payment = await _paymentService.GetByIdAsync(paymentId, cancellationToken);

        return payment is not null
            && await _rentScheduleService.CanAccessScheduleItemAsync(
                payment.RentScheduleItemId,
                _currentUserService.UserId,
                _currentUserService.Role,
                cancellationToken);
    }

    private async Task<IActionResult> ExecuteAsync(
        Func<Task<IActionResult>> action)
    {
        try
        {
            return await action();
        }
        catch (PaymentServiceException ex)
        {
            return ex.Error switch
            {
                PaymentServiceError.Validation =>
                    BadRequest(new { message = ex.Message }),

                PaymentServiceError.NotFound =>
                    NotFound(new { message = ex.Message }),

                PaymentServiceError.Conflict =>
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
