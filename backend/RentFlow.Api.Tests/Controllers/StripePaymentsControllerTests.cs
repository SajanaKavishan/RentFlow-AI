using System.Reflection;
using System.Text.Json;
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
using Xunit;

namespace RentFlow.Api.Tests.Controllers;

public sealed class StripePaymentsControllerTests
{
    [Fact]
    public void RoutesRequireTenantAndRequestRejectsExtraFields()
    {
        var controller = typeof(StripePaymentsController);
        Assert.Equal("Tenant", controller.GetCustomAttribute<AuthorizeAttribute>()?.Roles);
        Assert.Equal("api/payments", controller.GetCustomAttribute<RouteAttribute>()?.Template);
        Assert.Equal("stripe/create-intent",
            controller.GetMethod(nameof(StripePaymentsController.CreateIntent))!
                .GetCustomAttribute<HttpPostAttribute>()?.Template);
        Assert.Equal("{paymentId:guid}/stripe-status",
            controller.GetMethod(nameof(StripePaymentsController.GetStatus))!
                .GetCustomAttribute<HttpGetAttribute>()?.Template);

        var request = JsonSerializer.Deserialize<CreateStripeIntentRequestDto>(
            "{\"rentScheduleItemId\":\"" + Guid.NewGuid() + "\"}",
            new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
        Assert.NotNull(request);
        Assert.Throws<JsonException>(() => JsonSerializer.Deserialize<CreateStripeIntentRequestDto>(
            "{\"rentScheduleItemId\":\"" + Guid.NewGuid() + "\",\"amount\":1}",
            new JsonSerializerOptions { PropertyNameCaseInsensitive = true }));
    }

    [Fact]
    public async Task CreateReturnsSecretOnlyToAuthenticatedTenantAndNeverReturnsSecretKey()
    {
        var tenantId = Guid.NewGuid();
        var scheduleId = Guid.NewGuid();
        var service = new StubStripePaymentService
        {
            CreateResult = new StripeIntentResponseDto(
                Guid.NewGuid(), "fake_client_secret", "fake_publishable_key", "lkr",
                145_000m, PaymentStatus.Pending, "requires_payment_method")
        };
        var controller = CreateController(service, tenantId);
        var result = await controller.CreateIntent(
            new CreateStripeIntentRequestDto { RentScheduleItemId = scheduleId },
            CancellationToken.None);

        var ok = Assert.IsType<OkObjectResult>(result);
        var response = Assert.IsType<StripeIntentResponseDto>(ok.Value);
        Assert.Equal("fake_client_secret", response.ClientSecret);
        Assert.Equal(tenantId, service.LastTenantId);
        Assert.Equal(scheduleId, service.LastScheduleId);
        Assert.Equal("no-store", controller.Response.Headers.CacheControl.ToString());
        var json = JsonSerializer.Serialize(response);
        Assert.DoesNotContain("SecretKey", json);
        Assert.DoesNotContain("WebhookSecret", json);

        var anonymous = CreateController(service, null);
        Assert.IsType<UnauthorizedObjectResult>(await anonymous.CreateIntent(
            new CreateStripeIntentRequestDto { RentScheduleItemId = scheduleId },
            CancellationToken.None));
    }

    [Fact]
    public async Task StatusResponseNeverContainsClientSecret()
    {
        var tenantId = Guid.NewGuid();
        var paymentId = Guid.NewGuid();
        var service = new StubStripePaymentService
        {
            StatusResult = new StripePaymentStatusDto(
                paymentId, PaymentStatus.Pending, "requires_payment_method", null)
        };
        var controller = CreateController(service, tenantId);
        var result = await controller.GetStatus(paymentId, CancellationToken.None);

        var response = Assert.IsType<StripePaymentStatusDto>(
            Assert.IsType<OkObjectResult>(result).Value);
        Assert.Equal(paymentId, response.PaymentId);
        Assert.Equal(tenantId, service.LastTenantId);
        Assert.Equal("no-store", controller.Response.Headers.CacheControl.ToString());
        Assert.DoesNotContain("ClientSecret", JsonSerializer.Serialize(response));
    }

    [Theory]
    [InlineData(PaymentServiceError.Validation, 400)]
    [InlineData(PaymentServiceError.NotFound, 404)]
    [InlineData(PaymentServiceError.Conflict, 409)]
    [InlineData(PaymentServiceError.TemporaryFailure, 503)]
    [InlineData(PaymentServiceError.ExternalFailure, 502)]
    public async Task CreateMapsSafeServiceErrors(PaymentServiceError error, int statusCode)
    {
        var service = new StubStripePaymentService
        {
            CreateError = error switch
            {
                PaymentServiceError.Validation => PaymentServiceException.Validation("Invalid payment."),
                PaymentServiceError.NotFound => PaymentServiceException.NotFound("Payment not found."),
                PaymentServiceError.Conflict => PaymentServiceException.Conflict("Payment conflict."),
                PaymentServiceError.TemporaryFailure => PaymentServiceException.TemporaryFailure(
                    "Payment service temporarily unavailable."),
                _ => PaymentServiceException.ExternalFailure("Payment service unavailable.")
            }
        };
        var controller = CreateController(service, Guid.NewGuid());
        var result = await controller.CreateIntent(
            new CreateStripeIntentRequestDto { RentScheduleItemId = Guid.NewGuid() },
            CancellationToken.None);
        Assert.Equal(statusCode, Assert.IsAssignableFrom<ObjectResult>(result).StatusCode);
    }

    private static StripePaymentsController CreateController(
        IStripePaymentService service, Guid? userId) => new(
            service,
            new StubCurrentUser(userId),
            new StripeWebhookVerifier(Options.Create(new StripePaymentOptions
            {
                WebhookSecret = "fake-webhook-secret"
            })))
        {
            ControllerContext = new ControllerContext
            {
                HttpContext = new DefaultHttpContext()
            }
        };

    private sealed class StubCurrentUser(Guid? userId) : ICurrentUserService
    {
        public bool IsAuthenticated => userId.HasValue;
        public Guid? UserId => userId;
        public UserRole? Role => userId.HasValue ? UserRole.Tenant : null;
    }

    private sealed class StubStripePaymentService : IStripePaymentService
    {
        public StripeIntentResponseDto? CreateResult { get; set; }
        public StripePaymentStatusDto? StatusResult { get; set; }
        public PaymentServiceException? CreateError { get; set; }
        public Guid? LastTenantId { get; private set; }
        public Guid? LastScheduleId { get; private set; }

        public Task<StripeIntentResponseDto> CreateOrResumeAsync(
            Guid rentScheduleItemId, Guid tenantId,
            CancellationToken cancellationToken = default)
        {
            LastTenantId = tenantId;
            LastScheduleId = rentScheduleItemId;
            if (CreateError is not null)
            {
                throw CreateError;
            }

            return Task.FromResult(CreateResult!);
        }

        public Task<StripePaymentStatusDto> GetStatusAsync(
            Guid paymentId, Guid tenantId,
            CancellationToken cancellationToken = default)
        {
            LastTenantId = tenantId;
            return Task.FromResult(StatusResult!);
        }

        public Task<StripeWebhookProcessingResult> ProcessWebhookAsync(
            string paymentIntentId,
            CancellationToken cancellationToken = default) =>
            Task.FromResult(StripeWebhookProcessingResult.UnknownPaymentIntent);
    }
}
