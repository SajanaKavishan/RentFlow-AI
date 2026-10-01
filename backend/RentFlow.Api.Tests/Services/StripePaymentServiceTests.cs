using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using RentFlow.Api.Configuration;
using RentFlow.Api.Data;
using RentFlow.Api.DTOs.Payments;
using RentFlow.Api.Models;
using RentFlow.Api.Services;
using RentFlow.Api.Services.Interfaces;
using Xunit;

namespace RentFlow.Api.Tests.Services;

public sealed class StripePaymentServiceTests
{
    [Theory]
    [InlineData(RentScheduleStatus.Pending)]
    [InlineData(RentScheduleStatus.Overdue)]
    public async Task Create_ReservesStripePaymentAndUsesServerAmount(
        RentScheduleStatus scheduleStatus)
    {
        await using var fixture = await Fixture.CreateAsync(scheduleStatus);

        var result = await fixture.Service.CreateOrResumeAsync(
            fixture.Schedule.Id, fixture.TenantId);

        var payment = await fixture.Db.Payments.SingleAsync();
        var request = Assert.Single(fixture.Gateway.CreateRequests);
        Assert.Equal(payment.Id, result.PaymentId);
        Assert.Equal(145_000m, result.Amount);
        Assert.Equal("lkr", result.Currency);
        Assert.Equal(PaymentStatus.Pending, result.PaymentStatus);
        Assert.Equal("requires_payment_method", result.Status);
        Assert.NotNull(result.ClientSecret);
        Assert.Equal(fixture.PublishableKey, result.PublishableKey);
        Assert.Equal(PaymentProvider.Stripe, payment.Provider);
        Assert.Equal(PaymentStatus.Pending, payment.Status);
        Assert.Equal("Stripe", payment.PaymentMethod);
        Assert.Null(payment.TransactionReference);
        Assert.Equal("pi_fake_1", payment.StripePaymentIntentId);
        Assert.Equal(14_500_000L, request.AmountMinorUnits);
        Assert.Equal("lkr", request.Currency);
        Assert.Equal($"rentflow-payment-{payment.Id:D}", request.IdempotencyKey);
        Assert.Equal(payment.Id.ToString("D"), request.Metadata["rentflowPaymentId"]);
        Assert.Equal(fixture.Schedule.Id.ToString("D"), request.Metadata["rentScheduleItemId"]);
        Assert.Equal(fixture.TenantId.ToString("D"), request.Metadata["tenantId"]);
        Assert.Equal(3, request.Metadata.Count);
    }

    [Fact]
    public async Task SecondRequest_ResumesOneInternalAndExternalIntent()
    {
        await using var fixture = await Fixture.CreateAsync();
        var first = await fixture.Service.CreateOrResumeAsync(fixture.Schedule.Id, fixture.TenantId);
        var second = await fixture.Service.CreateOrResumeAsync(fixture.Schedule.Id, fixture.TenantId);

        Assert.Equal(first.PaymentId, second.PaymentId);
        Assert.Equal(first.ClientSecret, second.ClientSecret);
        Assert.Single(fixture.Db.Payments);
        Assert.Single(fixture.Gateway.Intents);
        Assert.Single(fixture.Gateway.CreateRequests);
        Assert.Equal(1, fixture.Gateway.RetrieveCount);
    }

    [Fact]
    public async Task ResumeOfSucceededIntentSettlesWithoutReturningClientSecret()
    {
        await using var fixture = await Fixture.CreateAsync();
        var first = await fixture.Service.CreateOrResumeAsync(fixture.Schedule.Id, fixture.TenantId);
        fixture.Gateway.Status = "succeeded";

        var resumed = await fixture.Service.CreateOrResumeAsync(
            fixture.Schedule.Id, fixture.TenantId);

        Assert.Equal(first.PaymentId, resumed.PaymentId);
        Assert.Equal(PaymentStatus.Completed, resumed.PaymentStatus);
        Assert.Null(resumed.ClientSecret);
        Assert.Equal(RentScheduleStatus.Paid, fixture.Schedule.Status);
        Assert.Single(fixture.Gateway.CreateRequests);
    }

    [Fact]
    public async Task Timeout_KeepsReservationAndRetryUsesSameIdempotencyKey()
    {
        await using var fixture = await Fixture.CreateAsync();
        fixture.Gateway.FailFirstCreateAfterSavingIntent = true;

        var exception = await Assert.ThrowsAsync<PaymentServiceException>(() =>
            fixture.Service.CreateOrResumeAsync(fixture.Schedule.Id, fixture.TenantId));
        Assert.Equal(PaymentServiceError.TemporaryFailure, exception.Error);
        var reserved = await fixture.Db.Payments.SingleAsync();
        Assert.Equal(PaymentStatus.Pending, reserved.Status);
        Assert.Null(reserved.StripePaymentIntentId);

        var retry = await fixture.Service.CreateOrResumeAsync(
            fixture.Schedule.Id, fixture.TenantId);
        Assert.Equal(reserved.Id, retry.PaymentId);
        Assert.Equal("pi_fake_1", reserved.StripePaymentIntentId);
        Assert.Equal(2, fixture.Gateway.CreateRequests.Count);
        Assert.Equal(fixture.Gateway.CreateRequests[0].IdempotencyKey,
            fixture.Gateway.CreateRequests[1].IdempotencyKey);
        Assert.Single(fixture.Gateway.Intents);
        Assert.Single(fixture.Db.Payments);
    }

    [Fact]
    public async Task OldUnlinkedReservationNeverRecreatesExternalIntentAfterKeyExpiry()
    {
        await using var fixture = await Fixture.CreateAsync();
        var reservation = fixture.NewPayment(PaymentStatus.Pending, PaymentProvider.Stripe);
        reservation.CreatedAt = DateTimeOffset.UtcNow.AddHours(-24);
        fixture.Db.Payments.Add(reservation);
        await fixture.Db.SaveChangesAsync();

        var error = await Assert.ThrowsAsync<PaymentServiceException>(() =>
            fixture.Service.CreateOrResumeAsync(fixture.Schedule.Id, fixture.TenantId));
        Assert.Equal(PaymentServiceError.Conflict, error.Error);
        Assert.Single(fixture.Db.Payments);
        Assert.Empty(fixture.Gateway.CreateRequests);
    }

    [Fact]
    public async Task PaidScheduleAndOtherTenantAreRejectedWithoutGatewayCall()
    {
        await using var fixture = await Fixture.CreateAsync(RentScheduleStatus.Paid);
        var paid = await Assert.ThrowsAsync<PaymentServiceException>(() =>
            fixture.Service.CreateOrResumeAsync(fixture.Schedule.Id, fixture.TenantId));
        Assert.Equal(PaymentServiceError.Conflict, paid.Error);

        var otherTenant = await Assert.ThrowsAsync<PaymentServiceException>(() =>
            fixture.Service.CreateOrResumeAsync(fixture.Schedule.Id, Guid.NewGuid()));
        Assert.Equal(PaymentServiceError.NotFound, otherTenant.Error);
        Assert.Empty(fixture.Db.Payments);
        Assert.Empty(fixture.Gateway.CreateRequests);
    }

    [Fact]
    public async Task InactiveLeaseIsRejected()
    {
        await using var fixture = await Fixture.CreateAsync();
        fixture.Lease.Status = LeaseAgreementStatus.Terminated;
        await fixture.Db.SaveChangesAsync();

        var error = await Assert.ThrowsAsync<PaymentServiceException>(() =>
            fixture.Service.CreateOrResumeAsync(fixture.Schedule.Id, fixture.TenantId));
        Assert.Equal(PaymentServiceError.Conflict, error.Error);
        Assert.Empty(fixture.Gateway.CreateRequests);
    }

    [Theory]
    [InlineData(PaymentStatus.Completed, PaymentProvider.Manual)]
    [InlineData(PaymentStatus.Pending, PaymentProvider.Manual)]
    public async Task CompletedOrPendingManualPaymentBlocksStripe(
        PaymentStatus status, PaymentProvider provider)
    {
        await using var fixture = await Fixture.CreateAsync();
        fixture.Db.Payments.Add(fixture.NewPayment(status, provider));
        await fixture.Db.SaveChangesAsync();

        var error = await Assert.ThrowsAsync<PaymentServiceException>(() =>
            fixture.Service.CreateOrResumeAsync(fixture.Schedule.Id, fixture.TenantId));
        Assert.Equal(PaymentServiceError.Conflict, error.Error);
        Assert.Empty(fixture.Gateway.CreateRequests);
    }

    [Fact]
    public async Task ActiveStripeAttemptBlocksNewManualCreationAndSettlement()
    {
        await using var fixture = await Fixture.CreateAsync();
        await fixture.Service.CreateOrResumeAsync(fixture.Schedule.Id, fixture.TenantId);
        var manualService = new PaymentService(fixture.Db);

        var creationError = await Assert.ThrowsAsync<PaymentServiceException>(() =>
            manualService.CreateAsync(new CreatePaymentDto
            {
                RentScheduleItemId = fixture.Schedule.Id,
                PaymentMethod = "BankTransfer"
            }, fixture.TenantId));
        Assert.Equal(PaymentServiceError.Conflict, creationError.Error);

        var manual = fixture.NewPayment(PaymentStatus.Pending, PaymentProvider.Manual);
        fixture.Db.Payments.Add(manual);
        await fixture.Db.SaveChangesAsync();
        var settlementError = await Assert.ThrowsAsync<PaymentServiceException>(() =>
            manualService.CompleteAsync(manual.Id));
        Assert.Equal(PaymentServiceError.Conflict, settlementError.Error);
        Assert.Equal(PaymentStatus.Pending, manual.Status);
    }

    [Fact]
    public async Task FailedStripeAttemptAllowsNewReservation()
    {
        await using var fixture = await Fixture.CreateAsync();
        var failed = fixture.NewPayment(PaymentStatus.Failed, PaymentProvider.Stripe);
        failed.StripePaymentIntentId = "pi_old_failed";
        fixture.Db.Payments.Add(failed);
        await fixture.Db.SaveChangesAsync();

        var result = await fixture.Service.CreateOrResumeAsync(
            fixture.Schedule.Id, fixture.TenantId);

        Assert.NotEqual(failed.Id, result.PaymentId);
        Assert.Equal(2, await fixture.Db.Payments.CountAsync());
        Assert.Equal(PaymentStatus.Failed, failed.Status);
    }

    [Theory]
    [InlineData(0)]
    [InlineData(-1)]
    [InlineData(1_000_000)]
    public async Task UnchargeableAmountIsRejectedBeforeReservation(decimal amount)
    {
        await using var fixture = await Fixture.CreateAsync();
        fixture.Schedule.Amount = amount;
        await fixture.Db.SaveChangesAsync();

        var error = await Assert.ThrowsAsync<PaymentServiceException>(() =>
            fixture.Service.CreateOrResumeAsync(fixture.Schedule.Id, fixture.TenantId));
        Assert.Equal(PaymentServiceError.Validation, error.Error);
        Assert.Empty(fixture.Db.Payments);
    }

    [Fact]
    public async Task VerifiedSuccessCompletesPaymentAndScheduleIdempotently()
    {
        await using var fixture = await Fixture.CreateAsync();
        var created = await fixture.Service.CreateOrResumeAsync(fixture.Schedule.Id, fixture.TenantId);
        fixture.Gateway.Status = "succeeded";

        var first = await fixture.Service.GetStatusAsync(created.PaymentId, fixture.TenantId);
        var paidAt = first.PaidAt;
        var second = await fixture.Service.GetStatusAsync(created.PaymentId, fixture.TenantId);

        Assert.Equal(PaymentStatus.Completed, first.PaymentStatus);
        Assert.Equal(PaymentStatus.Completed, second.PaymentStatus);
        Assert.Equal(paidAt, second.PaidAt);
        Assert.NotNull(paidAt);
        Assert.Equal(RentScheduleStatus.Paid, fixture.Schedule.Status);
        Assert.Equal(PaymentStatus.Completed, (await fixture.Db.Payments.SingleAsync()).Status);
        Assert.Single(fixture.Db.Payments);
    }

    [Fact]
    public async Task VerifiedSuccessCannotSettleScheduleAlreadyPaidElsewhere()
    {
        await using var fixture = await Fixture.CreateAsync();
        var created = await fixture.Service.CreateOrResumeAsync(fixture.Schedule.Id, fixture.TenantId);
        fixture.Schedule.Status = RentScheduleStatus.Paid;
        var other = fixture.NewPayment(PaymentStatus.Completed, PaymentProvider.Manual);
        fixture.Db.Payments.Add(other);
        await fixture.Db.SaveChangesAsync();
        fixture.Gateway.Status = "succeeded";

        var error = await Assert.ThrowsAsync<PaymentServiceException>(() =>
            fixture.Service.GetStatusAsync(created.PaymentId, fixture.TenantId));
        Assert.Equal(PaymentServiceError.Conflict, error.Error);
        Assert.Equal(PaymentStatus.Pending,
            (await fixture.Db.Payments.SingleAsync(payment => payment.Id == created.PaymentId)).Status);
    }

    [Theory]
    [InlineData("amount")]
    [InlineData("currency")]
    [InlineData("intent")]
    [InlineData("metadata")]
    public async Task MismatchedProviderDetailsNeverSettle(string mismatch)
    {
        await using var fixture = await Fixture.CreateAsync();
        var created = await fixture.Service.CreateOrResumeAsync(fixture.Schedule.Id, fixture.TenantId);
        fixture.Gateway.Status = "succeeded";
        fixture.Gateway.Mismatch = mismatch;

        var error = await Assert.ThrowsAsync<PaymentServiceException>(() =>
            fixture.Service.GetStatusAsync(created.PaymentId, fixture.TenantId));

        Assert.Equal(PaymentServiceError.Conflict, error.Error);
        Assert.Equal(PaymentStatus.Pending, (await fixture.Db.Payments.SingleAsync()).Status);
        Assert.Equal(RentScheduleStatus.Pending, fixture.Schedule.Status);
    }

    [Fact]
    public async Task RetryableProviderStateStaysPendingAndStatusHasNoClientSecret()
    {
        await using var fixture = await Fixture.CreateAsync();
        var created = await fixture.Service.CreateOrResumeAsync(fixture.Schedule.Id, fixture.TenantId);
        var status = await fixture.Service.GetStatusAsync(created.PaymentId, fixture.TenantId);

        Assert.Equal("requires_payment_method", status.Status);
        Assert.Equal(PaymentStatus.Pending, status.PaymentStatus);
        Assert.Null(status.PaidAt);
        Assert.DoesNotContain("ClientSecret", status.GetType().GetProperties()
            .Select(property => property.Name));
    }

    [Fact]
    public async Task CanceledIntentFailsReservationAndAllowsLaterNewAttempt()
    {
        await using var fixture = await Fixture.CreateAsync();
        var created = await fixture.Service.CreateOrResumeAsync(fixture.Schedule.Id, fixture.TenantId);
        fixture.Gateway.Status = "canceled";
        var canceled = await fixture.Service.GetStatusAsync(created.PaymentId, fixture.TenantId);
        Assert.Equal(PaymentStatus.Failed, canceled.PaymentStatus);
        Assert.Equal(RentScheduleStatus.Pending, fixture.Schedule.Status);

        fixture.Gateway.Status = "requires_payment_method";
        var retry = await fixture.Service.CreateOrResumeAsync(fixture.Schedule.Id, fixture.TenantId);
        Assert.NotEqual(created.PaymentId, retry.PaymentId);
        Assert.Equal(2, fixture.Db.Payments.Count());
    }

    [Fact]
    public async Task StatusRequiresOwnershipAndStripeProvider()
    {
        await using var fixture = await Fixture.CreateAsync();
        var created = await fixture.Service.CreateOrResumeAsync(fixture.Schedule.Id, fixture.TenantId);
        var foreign = await Assert.ThrowsAsync<PaymentServiceException>(() =>
            fixture.Service.GetStatusAsync(created.PaymentId, Guid.NewGuid()));
        Assert.Equal(PaymentServiceError.NotFound, foreign.Error);

        var manual = fixture.NewPayment(PaymentStatus.Pending, PaymentProvider.Manual);
        fixture.Db.Payments.Add(manual);
        await fixture.Db.SaveChangesAsync();
        var wrongProvider = await Assert.ThrowsAsync<PaymentServiceException>(() =>
            fixture.Service.GetStatusAsync(manual.Id, fixture.TenantId));
        Assert.Equal(PaymentServiceError.Validation, wrongProvider.Error);
    }

    private sealed class Fixture : IAsyncDisposable
    {
        private Fixture(ApplicationDbContext db, Guid tenantId, LeaseAgreement lease,
            RentScheduleItem schedule)
        {
            Db = db;
            TenantId = tenantId;
            Lease = lease;
            Schedule = schedule;
            Service = new StripePaymentService(db, Gateway,
                Options.Create(new StripePaymentOptions { PublishableKey = PublishableKey }));
        }

        public ApplicationDbContext Db { get; }
        public Guid TenantId { get; }
        public LeaseAgreement Lease { get; }
        public RentScheduleItem Schedule { get; }
        public FakeGateway Gateway { get; } = new();
        public StripePaymentService Service { get; }
        public string PublishableKey { get; } = "pk_" + "test_fake_only";

        public static async Task<Fixture> CreateAsync(
            RentScheduleStatus status = RentScheduleStatus.Pending)
        {
            var db = new ApplicationDbContext(
                new DbContextOptionsBuilder<ApplicationDbContext>()
                    .UseInMemoryDatabase(Guid.NewGuid().ToString()).Options);
            var tenantId = Guid.NewGuid();
            var lease = new LeaseAgreement
            {
                RentalOfferId = Guid.NewGuid(),
                TenantId = tenantId,
                PropertyId = Guid.NewGuid(),
                MonthlyRent = 145_000m,
                SecurityDeposit = 290_000m,
                StartDate = new DateOnly(2026, 10, 1),
                EndDate = new DateOnly(2027, 9, 30),
                Status = LeaseAgreementStatus.Active
            };
            var schedule = new RentScheduleItem
            {
                LeaseAgreementId = lease.Id,
                DueDate = new DateOnly(2026, 10, 1),
                Amount = 145_000m,
                Status = status
            };
            db.LeaseAgreements.Add(lease);
            db.RentScheduleItems.Add(schedule);
            await db.SaveChangesAsync();
            return new Fixture(db, tenantId, lease, schedule);
        }

        public Payment NewPayment(PaymentStatus status, PaymentProvider provider) => new()
        {
            RentScheduleItemId = Schedule.Id,
            TenantId = TenantId,
            Amount = Schedule.Amount,
            PaymentMethod = provider.ToString(),
            Provider = provider,
            Status = status
        };

        public ValueTask DisposeAsync() => Db.DisposeAsync();
    }

    private sealed class FakeGateway : IStripePaymentGateway
    {
        private readonly Dictionary<string, StripePaymentIntentResult> _byKey = new();
        public List<StripePaymentIntentRequest> CreateRequests { get; } = new();
        public IReadOnlyCollection<StripePaymentIntentResult> Intents => _byKey.Values;
        public int RetrieveCount { get; private set; }
        public bool FailFirstCreateAfterSavingIntent { get; set; }
        public string Status { get; set; } = "requires_payment_method";
        public string? Mismatch { get; set; }

        public Task<StripePaymentIntentResult> CreateAsync(
            StripePaymentIntentRequest request,
            CancellationToken cancellationToken = default)
        {
            CreateRequests.Add(request);
            if (!_byKey.TryGetValue(request.IdempotencyKey, out var intent))
            {
                intent = new StripePaymentIntentResult(
                    $"pi_fake_{_byKey.Count + 1}", "fake_client_secret", Status,
                    request.AmountMinorUnits, request.Currency,
                    new Dictionary<string, string>(request.Metadata));
                _byKey.Add(request.IdempotencyKey, intent);
            }

            if (FailFirstCreateAfterSavingIntent && CreateRequests.Count == 1)
            {
                throw new StripeGatewayException(StripeGatewayError.Temporary,
                    "Provider timeout (fake).");
            }

            return Task.FromResult(intent);
        }

        public Task<StripePaymentIntentResult> RetrieveAsync(
            string paymentIntentId,
            CancellationToken cancellationToken = default)
        {
            RetrieveCount++;
            var intent = _byKey.Values.Single(value => value.Id == paymentIntentId);
            intent = intent with { Status = Status };
            intent = Mismatch switch
            {
                "amount" => intent with { AmountMinorUnits = intent.AmountMinorUnits + 1 },
                "currency" => intent with { Currency = "usd" },
                "intent" => intent with { Id = "pi_wrong" },
                "metadata" => intent with { Metadata = new Dictionary<string, string>() },
                _ => intent
            };
            return Task.FromResult(intent);
        }
    }
}
