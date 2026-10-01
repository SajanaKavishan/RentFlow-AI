using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using RentFlow.Api.DTOs.Payments;
using RentFlow.Api.Services;
using RentFlow.Api.Services.Interfaces;

namespace RentFlow.Api.Controllers;

[ApiController]
[Route("api/payments")]
[Authorize(Roles = "Tenant")]
public sealed class StripePaymentsController(
    IStripePaymentService paymentService,
    ICurrentUserService currentUserService) : ControllerBase
{
    [HttpPost("stripe/create-intent")]
    public Task<IActionResult> CreateIntent(
        [FromBody] CreateStripeIntentRequestDto request,
        CancellationToken cancellationToken) => ExecuteAsync(async tenantId =>
    {
        var response = await paymentService.CreateOrResumeAsync(
            request.RentScheduleItemId, tenantId, cancellationToken);
        Response.Headers.CacheControl = "no-store";
        return Ok(response);
    });

    [HttpGet("{paymentId:guid}/stripe-status")]
    public Task<IActionResult> GetStatus(
        Guid paymentId,
        CancellationToken cancellationToken) => ExecuteAsync(async tenantId =>
    {
        var response = await paymentService.GetStatusAsync(
            paymentId, tenantId, cancellationToken);
        Response.Headers.CacheControl = "no-store";
        return Ok(response);
    });

    private async Task<IActionResult> ExecuteAsync(Func<Guid, Task<IActionResult>> action)
    {
        if (currentUserService.UserId is not Guid tenantId)
        {
            return Unauthorized(new { message = "Authenticated user ID was not found." });
        }

        try
        {
            return await action(tenantId);
        }
        catch (PaymentServiceException ex)
        {
            return ex.Error switch
            {
                PaymentServiceError.Validation => BadRequest(new { message = ex.Message }),
                PaymentServiceError.NotFound => NotFound(new { message = ex.Message }),
                PaymentServiceError.Conflict => Conflict(new { message = ex.Message }),
                PaymentServiceError.TemporaryFailure => StatusCode(
                    StatusCodes.Status503ServiceUnavailable, new { message = ex.Message }),
                PaymentServiceError.ExternalFailure => StatusCode(
                    StatusCodes.Status502BadGateway, new { message = ex.Message }),
                _ => StatusCode(StatusCodes.Status500InternalServerError,
                    new { message = "An unexpected error occurred." })
            };
        }
        catch
        {
            return StatusCode(StatusCodes.Status500InternalServerError,
                new { message = "An unexpected error occurred." });
        }
    }
}
