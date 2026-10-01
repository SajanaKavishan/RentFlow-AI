using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Storage;
using Microsoft.Extensions.Options;
using Npgsql;
using RentFlow.Api.Configuration;
using RentFlow.Api.DTOs.Payments;
using RentFlow.Api.Data;
using RentFlow.Api.Models;
using RentFlow.Api.Services.Interfaces;

namespace RentFlow.Api.Services;

public sealed class StripePaymentService(
    ApplicationDbContext dbContext,
    IStripePaymentGateway gateway,
    IOptions<StripePaymentOptions> options) : IStripePaymentService
{
    private const long MaximumStripeAmountMinorUnits = 99_999_999;
    private static readonly TimeSpan IdempotencyRetryWindow = TimeSpan.FromHours(23);

    public async Task<StripeIntentResponseDto> CreateOrResumeAsync(
        Guid rentScheduleItemId,
        Guid tenantId,
        CancellationToken cancellationToken = default)
    {
        if (rentScheduleItemId == Guid.Empty)
        {
            throw PaymentServiceException.Validation("Rent schedule item is required.");
        }

        var publishableKey = options.Value.PublishableKey;
        if (string.IsNullOrWhiteSpace(publishableKey)
            || !publishableKey.StartsWith("pk_test_", StringComparison.Ordinal))
        {
            throw PaymentServiceException.ExternalFailure(
                "Stripe test-mode payment service is unavailable.");
        }

        var schedule = await dbContext.RentScheduleItems
            .Include(item => item.LeaseAgreement)
            .SingleOrDefaultAsync(item => item.Id == rentScheduleItemId, cancellationToken);
        if (schedule is null || schedule.LeaseAgreement.TenantId != tenantId)
        {
            throw PaymentServiceException.NotFound("Rent schedule item was not found.");
        }

        if (schedule.LeaseAgreement.Status != LeaseAgreementStatus.Active
            || schedule.Status is not (RentScheduleStatus.Pending or RentScheduleStatus.Overdue))
        {
            throw PaymentServiceException.Conflict("This rent schedule item is not payable.");
        }

        var amountMinorUnits = ToStripeAmount(schedule.Amount);

        if (await dbContext.Payments.AnyAsync(payment =>
                payment.RentScheduleItemId == schedule.Id
                && payment.Status == PaymentStatus.Completed, cancellationToken))
        {
            throw PaymentServiceException.Conflict(
                "A completed payment already exists for this rent schedule item.");
        }

        if (await dbContext.Payments.AnyAsync(payment =>
                payment.RentScheduleItemId == schedule.Id
                && payment.Provider == PaymentProvider.Manual
                && payment.Status == PaymentStatus.Pending, cancellationToken))
        {
            throw PaymentServiceException.Conflict(
                "Resolve the pending manual payment before starting a Stripe payment.");
        }

        var payment = await dbContext.Payments.SingleOrDefaultAsync(payment =>
            payment.RentScheduleItemId == schedule.Id
            && payment.Provider == PaymentProvider.Stripe
            && payment.Status == PaymentStatus.Pending, cancellationToken);

        if (payment is null)
        {
            payment = new Payment
            {
                RentScheduleItemId = schedule.Id,
                TenantId = tenantId,
                Amount = schedule.Amount,
                Provider = PaymentProvider.Stripe,
                PaymentMethod = "Stripe",
                TransactionReference = null,
                Status = PaymentStatus.Pending,
                CreatedAt = DateTimeOffset.UtcNow
            };
            dbContext.Payments.Add(payment);
            try
            {
                await dbContext.SaveChangesAsync(cancellationToken);
            }
            catch (DbUpdateException ex) when (IsPendingStripeRace(ex))
            {
                dbContext.Entry(payment).State = EntityState.Detached;
                payment = await dbContext.Payments.SingleOrDefaultAsync(existing =>
                    existing.RentScheduleItemId == schedule.Id
                    && existing.Provider == PaymentProvider.Stripe
                    && existing.Status == PaymentStatus.Pending, cancellationToken);
                if (payment is null)
                {
                    throw PaymentServiceException.Conflict(
                        "The Stripe payment attempt changed. Please retry.");
                }
            }
        }

        if (payment.TenantId != tenantId || payment.Amount != schedule.Amount)
        {
            throw PaymentServiceException.Conflict(
                "The pending Stripe payment does not match this rent schedule item.");
        }

        StripePaymentIntentResult intent;
        if (payment.StripePaymentIntentId is not null)
        {
            intent = await RetrieveAsync(payment.StripePaymentIntentId, cancellationToken);
        }
        else
        {
            // Stripe may forget idempotency keys after 24 hours. Never create a second
            // external intent for a reservation whose first response was lost.
            if (DateTimeOffset.UtcNow - payment.CreatedAt >= IdempotencyRetryWindow)
            {
                throw PaymentServiceException.Conflict(
                    "This payment attempt needs support before it can be retried.");
            }

            intent = await CreateIntentAsync(payment, amountMinorUnits, cancellationToken);
            ValidateIntent(payment, intent, amountMinorUnits);
            payment.StripePaymentIntentId = intent.Id;
            payment.UpdatedAt = DateTimeOffset.UtcNow;
            try
            {
                await dbContext.SaveChangesAsync(cancellationToken);
            }
            catch (DbUpdateException ex) when (IsStripeIntentIdRace(ex))
            {
                throw PaymentServiceException.Conflict(
                    "The Stripe payment attempt changed. Please retry.");
            }
        }

        var status = await ApplyVerifiedIntentAsync(payment, intent, cancellationToken);
        if (status.PaymentStatus == PaymentStatus.Failed)
        {
            throw PaymentServiceException.Conflict(
                "The Stripe payment attempt was canceled. Please start a new attempt.");
        }

        if (status.PaymentStatus == PaymentStatus.Pending
            && string.IsNullOrWhiteSpace(intent.ClientSecret))
        {
            throw PaymentServiceException.ExternalFailure(
                "Stripe could not prepare this payment attempt.");
        }

        return new StripeIntentResponseDto(
            payment.Id,
            status.PaymentStatus == PaymentStatus.Pending ? intent.ClientSecret : null,
            publishableKey,
            options.Value.StripeCurrency,
            payment.Amount,
            status.PaymentStatus,
            status.Status);
    }

    public async Task<StripePaymentStatusDto> GetStatusAsync(
        Guid paymentId,
        Guid tenantId,
        CancellationToken cancellationToken = default)
    {
        var payment = await dbContext.Payments
            .Include(item => item.RentScheduleItem)
            .SingleOrDefaultAsync(item => item.Id == paymentId, cancellationToken);
        if (payment is null || payment.TenantId != tenantId)
        {
            throw PaymentServiceException.NotFound("Payment was not found.");
        }

        if (payment.Provider != PaymentProvider.Stripe)
        {
            throw PaymentServiceException.Validation("This is not a Stripe payment.");
        }

        if (payment.StripePaymentIntentId is null)
        {
            throw PaymentServiceException.TemporaryFailure(
                "The Stripe payment attempt is still being prepared. Please retry.");
        }

        var intent = await RetrieveAsync(payment.StripePaymentIntentId, cancellationToken);
        return await ApplyVerifiedIntentAsync(payment, intent, cancellationToken);
    }

    public async Task<StripeWebhookProcessingResult> ProcessWebhookAsync(
        string paymentIntentId,
        CancellationToken cancellationToken = default)
    {
        var payment = await dbContext.Payments.SingleOrDefaultAsync(item =>
            item.StripePaymentIntentId == paymentIntentId, cancellationToken);
        if (payment is null)
        {
            return StripeWebhookProcessingResult.UnknownPaymentIntent;
        }

        if (payment.Provider != PaymentProvider.Stripe)
        {
            throw PaymentServiceException.Conflict(
                "The Stripe payment mapping is invalid.");
        }

        var intent = await RetrieveAsync(paymentIntentId, cancellationToken);
        await ApplyVerifiedIntentAsync(payment, intent, cancellationToken);
        return StripeWebhookProcessingResult.Processed;
    }

    private async Task<StripePaymentIntentResult> CreateIntentAsync(
        Payment payment,
        long amountMinorUnits,
        CancellationToken cancellationToken)
    {
        var request = new StripePaymentIntentRequest(
            amountMinorUnits,
            options.Value.StripeCurrency,
            $"rentflow-payment-{payment.Id:D}",
            new Dictionary<string, string>
            {
                ["rentflowPaymentId"] = payment.Id.ToString("D"),
                ["rentScheduleItemId"] = payment.RentScheduleItemId.ToString("D"),
                ["tenantId"] = payment.TenantId.ToString("D")
            });
        try
        {
            return await gateway.CreateAsync(request, cancellationToken);
        }
        catch (StripeGatewayException ex)
        {
            throw MapGatewayFailure(ex);
        }
    }

    private async Task<StripePaymentIntentResult> RetrieveAsync(
        string paymentIntentId,
        CancellationToken cancellationToken)
    {
        try
        {
            return await gateway.RetrieveAsync(paymentIntentId, cancellationToken);
        }
        catch (StripeGatewayException ex)
        {
            throw MapGatewayFailure(ex);
        }
    }

    private async Task<StripePaymentStatusDto> ApplyVerifiedIntentAsync(
        Payment payment,
        StripePaymentIntentResult intent,
        CancellationToken cancellationToken)
    {
        ValidateIntent(payment, intent, ToStripeAmount(payment.Amount));

        await using IDbContextTransaction? transaction = dbContext.Database.IsRelational()
            ? await dbContext.Database.BeginTransactionAsync(cancellationToken)
            : null;

        if (transaction is not null)
        {
            // Serialize settlement of this one payment so duplicate webhook and
            // status requests cannot overwrite its original PaidAt value.
            await dbContext.Payments.FromSqlInterpolated(
                $"SELECT * FROM \"Payments\" WHERE \"Id\" = {payment.Id} FOR UPDATE")
                .ToListAsync(cancellationToken);
        }

        await dbContext.Entry(payment).ReloadAsync(cancellationToken);
        var schedule = await dbContext.RentScheduleItems
            .SingleAsync(item => item.Id == payment.RentScheduleItemId, cancellationToken);
        await dbContext.Entry(schedule).ReloadAsync(cancellationToken);

        if (payment.StripePaymentIntentId != intent.Id
            || schedule.Amount != payment.Amount)
        {
            throw PaymentServiceException.Conflict(
                "The Stripe payment details do not match this rent schedule item.");
        }

        var safeStatus = SafeStatus(intent.Status);
        if (payment.Status == PaymentStatus.Completed)
        {
            return new StripePaymentStatusDto(payment.Id, payment.Status, "succeeded", payment.PaidAt);
        }

        if (payment.Status == PaymentStatus.Failed)
        {
            return new StripePaymentStatusDto(payment.Id, payment.Status, safeStatus, payment.PaidAt);
        }

        if (safeStatus == "succeeded")
        {
            if (schedule.Status == RentScheduleStatus.Paid
                || await dbContext.Payments.AnyAsync(existing =>
                    existing.RentScheduleItemId == schedule.Id
                    && existing.Id != payment.Id
                    && existing.Status == PaymentStatus.Completed, cancellationToken))
            {
                throw PaymentServiceException.Conflict(
                    "This rent schedule item has already been paid.");
            }

            var utcNow = DateTimeOffset.UtcNow;
            var now = new DateTimeOffset(
                utcNow.Ticks - utcNow.Ticks % 10, TimeSpan.Zero);
            payment.Status = PaymentStatus.Completed;
            payment.PaidAt = now;
            payment.UpdatedAt = now;
            schedule.Status = RentScheduleStatus.Paid;
            schedule.UpdatedAt = now;
        }
        else if (safeStatus == "canceled")
        {
            payment.Status = PaymentStatus.Failed;
            payment.UpdatedAt = DateTimeOffset.UtcNow;
        }

        if (dbContext.ChangeTracker.HasChanges())
        {
            try
            {
                await dbContext.SaveChangesAsync(cancellationToken);
            }
            catch (DbUpdateException ex) when (IsCompletedPaymentRace(ex))
            {
                if (transaction is not null)
                {
                    await transaction.RollbackAsync(cancellationToken);
                }

                dbContext.ChangeTracker.Clear();
                var anotherCompletionWon = await dbContext.Payments.AsNoTracking()
                    .AnyAsync(existing => existing.RentScheduleItemId == schedule.Id
                        && existing.Id != payment.Id
                        && existing.Status == PaymentStatus.Completed,
                        cancellationToken);
                if (!anotherCompletionWon)
                {
                    throw PaymentServiceException.TemporaryFailure(
                        "Payment settlement could not be confirmed. Please retry.");
                }

                throw PaymentServiceException.Conflict(
                    "This rent schedule item has already been paid.");
            }
        }

        if (transaction is not null)
        {
            await transaction.CommitAsync(cancellationToken);
        }

        return new StripePaymentStatusDto(payment.Id, payment.Status, safeStatus, payment.PaidAt);
    }

    private static void ValidateIntent(Payment payment, StripePaymentIntentResult intent,
        long expectedAmountMinorUnits)
    {
        if (!intent.Id.StartsWith("pi_", StringComparison.Ordinal)
            || intent.Id.Contains("_secret_", StringComparison.Ordinal)
            || payment.StripePaymentIntentId is not null
                && payment.StripePaymentIntentId != intent.Id
            || intent.AmountMinorUnits != expectedAmountMinorUnits
            || intent.Currency != "lkr"
            || !MatchesMetadata(intent.Metadata, "rentflowPaymentId", payment.Id)
            || !MatchesMetadata(intent.Metadata, "rentScheduleItemId", payment.RentScheduleItemId)
            || !MatchesMetadata(intent.Metadata, "tenantId", payment.TenantId))
        {
            throw PaymentServiceException.Conflict(
                "The Stripe payment details do not match this payment attempt.");
        }
    }

    private static bool MatchesMetadata(
        IReadOnlyDictionary<string, string> metadata, string key, Guid expected) =>
        metadata.TryGetValue(key, out var value)
        && Guid.TryParse(value, out var actual)
        && actual == expected;

    private static long ToStripeAmount(decimal amount)
    {
        try
        {
            var minorUnits = StripePaymentOptions.ToStripeMinorUnits(amount);
            if (minorUnits > MaximumStripeAmountMinorUnits)
            {
                throw new ArgumentOutOfRangeException(nameof(amount));
            }

            return minorUnits;
        }
        catch (Exception ex) when (ex is ArgumentOutOfRangeException or OverflowException)
        {
            throw PaymentServiceException.Validation(
                "The rent amount cannot be charged in LKR by Stripe.");
        }
    }

    private static string SafeStatus(string status) => status switch
    {
        "requires_payment_method" or "requires_confirmation" or "requires_action"
            or "processing" or "requires_capture" or "succeeded" or "canceled" => status,
        _ => "unknown"
    };

    private static PaymentServiceException MapGatewayFailure(StripeGatewayException error) =>
        error.Error == StripeGatewayError.Temporary
            ? PaymentServiceException.TemporaryFailure(
                "Stripe is temporarily unavailable. Please retry this payment attempt.")
            : PaymentServiceException.ExternalFailure(
                "Stripe could not process the payment request.");

    private static bool IsPendingStripeRace(DbUpdateException error) =>
        error.InnerException is PostgresException postgres
        && postgres.SqlState == PostgresErrorCodes.UniqueViolation
        && postgres.ConstraintName == "IX_Payments_RentScheduleItemId_PendingStripe";

    private static bool IsStripeIntentIdRace(DbUpdateException error) =>
        error.InnerException is PostgresException postgres
        && postgres.SqlState == PostgresErrorCodes.UniqueViolation
        && postgres.ConstraintName == "IX_Payments_StripePaymentIntentId";

    private static bool IsCompletedPaymentRace(DbUpdateException error) =>
        error.InnerException is PostgresException postgres
        && postgres.SqlState == PostgresErrorCodes.UniqueViolation
        && postgres.ConstraintName == "IX_Payments_RentScheduleItemId_Completed";
}
