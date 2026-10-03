using System.Text;
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
    ICurrentUserService currentUserService,
    IStripeWebhookVerifier webhookVerifier) : ControllerBase
{
    private const int MaximumWebhookBytes = 1_048_576;

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

    [HttpPost("stripe/webhook")]
    [AllowAnonymous]
    public async Task<IActionResult> Webhook(CancellationToken cancellationToken)
    {
        if (!Request.Headers.TryGetValue("Stripe-Signature", out var signature)
            || string.IsNullOrWhiteSpace(signature.ToString()))
        {
            return BadRequest(new { message = "Invalid webhook signature." });
        }

        StripeWebhookEvent stripeEvent;
        try
        {
            var rawBody = await ReadRawBodyAsync(cancellationToken);
            stripeEvent = webhookVerifier.Verify(rawBody, signature.ToString());
        }
        catch (StripeWebhookException ex)
        {
            return ex.Error == StripeWebhookError.NotConfigured
                ? StatusCode(StatusCodes.Status503ServiceUnavailable,
                    new { message = "Webhook processing is unavailable." })
                : BadRequest(new { message = "Invalid webhook request." });
        }
        catch (Exception ex) when (ex is InvalidDataException or DecoderFallbackException)
        {
            return BadRequest(new { message = "Invalid webhook request." });
        }

        if (stripeEvent.Type is not ("payment_intent.succeeded"
            or "payment_intent.payment_failed" or "payment_intent.canceled"))
        {
            return Ok(new { received = true });
        }

        if (string.IsNullOrWhiteSpace(stripeEvent.PaymentIntentId))
        {
            return Ok(new { received = true });
        }

        try
        {
            await paymentService.ProcessWebhookAsync(
                stripeEvent.PaymentIntentId, cancellationToken);
            return Ok(new { received = true });
        }
        catch (PaymentServiceException ex) when (ex.Error == PaymentServiceError.Conflict
            || ex.Error == PaymentServiceError.Validation)
        {
            // A verified event with a permanent mismatch cannot be repaired by
            // replaying the same delivery. Leave internal state untouched.
            return Ok(new { received = true });
        }
        catch
        {
            return StatusCode(StatusCodes.Status503ServiceUnavailable,
                new { message = "Webhook processing is temporarily unavailable." });
        }
    }

    private async Task<string> ReadRawBodyAsync(CancellationToken cancellationToken)
    {
        await using var body = new MemoryStream();
        var buffer = new byte[8192];
        while (true)
        {
            var read = await Request.Body.ReadAsync(buffer, cancellationToken);
            if (read == 0)
            {
                break;
            }

            if (body.Length + read > MaximumWebhookBytes)
            {
                throw new InvalidDataException("Webhook request is too large.");
            }

            await body.WriteAsync(buffer.AsMemory(0, read), cancellationToken);
        }

        return new UTF8Encoding(false, true).GetString(body.ToArray());
    }

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
