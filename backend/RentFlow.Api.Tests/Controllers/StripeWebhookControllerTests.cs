using System.Reflection;
using System.Text;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;
using RentFlow.Api.Configuration;
using RentFlow.Api.Controllers;
using RentFlow.Api.DTOs.Payments;
using RentFlow.Api.Models;
using RentFlow.Api.Services;
using RentFlow.Api.Services.Interfaces;
using Stripe;
using Xunit;

namespace RentFlow.Api.Tests.Controllers;

public sealed class StripeWebhookControllerTests
{
    private const string TestWebhookSecret = "fake-webhook-secret";

    [Fact]
    public void OnlyWebhookActionIsAnonymous()
    {
        var controller = typeof(StripePaymentsController);
        Assert.Equal("Tenant", controller.GetCustomAttribute<AuthorizeAttribute>()?.Roles);
        var webhook = controller.GetMethod(nameof(StripePaymentsController.Webhook))!;
        Assert.Equal("stripe/webhook", webhook.GetCustomAttribute<HttpPostAttribute>()?.Template);
        Assert.NotNull(webhook.GetCustomAttribute<AllowAnonymousAttribute>());
        Assert.Null(controller.GetMethod(nameof(StripePaymentsController.CreateIntent))!
            .GetCustomAttribute<AllowAnonymousAttribute>());
        Assert.Null(controller.GetMethod(nameof(StripePaymentsController.GetStatus))!
            .GetCustomAttribute<AllowAnonymousAttribute>());
    }

    [Fact]
    public async Task MissingOrInvalidSignatureIsRejectedBeforeProcessing()
    {
        var service = new StubService();
        var payload = EventPayload("payment_intent.succeeded", "pi_fake_1");
        var missing = CreateController(service, payload, null);
        Assert.IsType<BadRequestObjectResult>(await missing.Webhook(CancellationToken.None));

        var invalid = CreateController(service, payload, "t=1,v1=invalid");
        Assert.IsType<BadRequestObjectResult>(await invalid.Webhook(CancellationToken.None));
        Assert.Empty(service.ProcessedIds);
    }

    [Fact]
    public async Task SignatureUsesExactRawBodyAndIrrelevantEventIsIgnored()
    {
        var service = new StubService();
        var payload = "{\n  \"type\": \"customer.created\",\n  \"data\": {\"object\": {\"id\": \"cus_fake\"}}\n}";
        var signature = EventUtility.GenerateSignatureHeader(payload, TestWebhookSecret);
        var accepted = CreateController(service, payload, signature);
        Assert.IsType<OkObjectResult>(await accepted.Webhook(CancellationToken.None));
        Assert.Empty(service.ProcessedIds);

        var whitespaceChanged = CreateController(service, payload.Replace("  ", " "), signature);
        Assert.IsType<BadRequestObjectResult>(
            await whitespaceChanged.Webhook(CancellationToken.None));
    }

    [Theory]
    [InlineData("payment_intent.succeeded")]
    [InlineData("payment_intent.payment_failed")]
    [InlineData("payment_intent.canceled")]
    public async Task SignedRelevantEventPassesOnlyIntentIdToService(string eventType)
    {
        var service = new StubService();
        var payload = EventPayload(eventType, "pi_fake_1");
        var controller = CreateController(service, payload,
            EventUtility.GenerateSignatureHeader(payload, TestWebhookSecret));

        Assert.IsType<OkObjectResult>(await controller.Webhook(CancellationToken.None));
        Assert.Equal("pi_fake_1", Assert.Single(service.ProcessedIds));
    }

    [Fact]
    public async Task SignedEventWithMissingIntentIdIsAcknowledgedWithoutMutation()
    {
        var service = new StubService();
        var payload = EventPayload("payment_intent.succeeded", null);
        var controller = CreateController(service, payload,
            EventUtility.GenerateSignatureHeader(payload, TestWebhookSecret));
        Assert.IsType<OkObjectResult>(await controller.Webhook(CancellationToken.None));
        Assert.Empty(service.ProcessedIds);
    }

    [Theory]
    [InlineData(PaymentServiceError.Conflict, 200)]
    [InlineData(PaymentServiceError.TemporaryFailure, 503)]
    [InlineData(PaymentServiceError.ExternalFailure, 503)]
    public async Task ProcessingErrorsHaveSafeResponses(
        PaymentServiceError error, int expectedStatus)
    {
        var service = new StubService
        {
            Error = error switch
            {
                PaymentServiceError.Conflict => PaymentServiceException.Conflict("private mismatch"),
                PaymentServiceError.TemporaryFailure =>
                    PaymentServiceException.TemporaryFailure("private temporary detail"),
                _ => PaymentServiceException.ExternalFailure("private provider detail")
            }
        };
        var payload = EventPayload("payment_intent.succeeded", "pi_fake_1");
        var controller = CreateController(service, payload,
            EventUtility.GenerateSignatureHeader(payload, TestWebhookSecret));
        var response = Assert.IsAssignableFrom<ObjectResult>(
            await controller.Webhook(CancellationToken.None));
        Assert.Equal(expectedStatus, response.StatusCode);
        Assert.DoesNotContain("private", response.Value!.ToString()!);
        Assert.DoesNotContain(TestWebhookSecret, response.Value!.ToString()!);
    }

    [Fact]
    public async Task MissingWebhookConfigurationReturnsRetryableSafeResponse()
    {
        var service = new StubService();
        var payload = EventPayload("payment_intent.succeeded", "pi_fake_1");
        var controller = CreateController(service, payload,
            EventUtility.GenerateSignatureHeader(payload, TestWebhookSecret),
            webhookSecret: null);
        var response = Assert.IsType<ObjectResult>(await controller.Webhook(CancellationToken.None));
        Assert.Equal(503, response.StatusCode);
        Assert.Empty(service.ProcessedIds);
    }

    [Fact]
    public async Task UnknownMappedIntentIsAcknowledgedWithoutMutation()
    {
        var service = new StubService { Result = StripeWebhookProcessingResult.UnknownPaymentIntent };
        var payload = EventPayload("payment_intent.succeeded", "pi_unknown");
        var controller = CreateController(service, payload,
            EventUtility.GenerateSignatureHeader(payload, TestWebhookSecret));
        Assert.IsType<OkObjectResult>(await controller.Webhook(CancellationToken.None));
        Assert.Equal("pi_unknown", Assert.Single(service.ProcessedIds));
    }

    private static string EventPayload(string eventType, string? paymentIntentId) =>
        $"{{\"type\":\"{eventType}\",\"data\":{{\"object\":{{" +
        (paymentIntentId is null ? "" : $"\"id\":\"{paymentIntentId}\"") + "}}}";

    private static StripePaymentsController CreateController(
        IStripePaymentService service,
        string payload,
        string? signature,
        string? webhookSecret = TestWebhookSecret)
    {
        var context = new DefaultHttpContext();
        context.Request.Body = new MemoryStream(Encoding.UTF8.GetBytes(payload));
        if (signature is not null)
        {
            context.Request.Headers["Stripe-Signature"] = signature;
        }

        return new StripePaymentsController(
            service,
            new AnonymousCurrentUser(),
            new StripeWebhookVerifier(Options.Create(new StripePaymentOptions
            {
                WebhookSecret = webhookSecret
            })))
        {
            ControllerContext = new ControllerContext { HttpContext = context }
        };
    }

    private sealed class AnonymousCurrentUser : ICurrentUserService
    {
        public bool IsAuthenticated => false;
        public Guid? UserId => null;
        public UserRole? Role => null;
    }

    private sealed class StubService : IStripePaymentService
    {
        public List<string> ProcessedIds { get; } = new();
        public StripeWebhookProcessingResult Result { get; set; } =
            StripeWebhookProcessingResult.Processed;
        public PaymentServiceException? Error { get; set; }

        public Task<StripeWebhookProcessingResult> ProcessWebhookAsync(
            string paymentIntentId, CancellationToken cancellationToken = default)
        {
            ProcessedIds.Add(paymentIntentId);
            if (Error is not null)
            {
                throw Error;
            }

            return Task.FromResult(Result);
        }

        public Task<StripeIntentResponseDto> CreateOrResumeAsync(
            Guid rentScheduleItemId, Guid tenantId,
            CancellationToken cancellationToken = default) =>
            throw new InvalidOperationException("Not used by webhook tests.");

        public Task<StripePaymentStatusDto> GetStatusAsync(
            Guid paymentId, Guid tenantId,
            CancellationToken cancellationToken = default) =>
            throw new InvalidOperationException("Not used by webhook tests.");
    }
}
