using System.IdentityModel.Tokens.Jwt;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Claims;
using System.Text;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.IdentityModel.Tokens;
using RentFlow.Api.Controllers;
using RentFlow.Api.Data;
using RentFlow.Api.Models;
using RentFlow.Api.Services;
using RentFlow.Api.DTOs.LeaseAgreements;
using RentFlow.Api.DTOs.Payments;
using Xunit;

namespace RentFlow.Api.Tests.Authentication;

public sealed class LandlordActionCountersTests
{
    [Fact]
    public async Task AcceptedOfferPendingLeaseAndManualPaymentEmitOwnedPersistedEvents()
    {
        using var factory = new AuthApiFactory(); var landlord = Guid.NewGuid(); var tenant = Guid.NewGuid();
        using var client = Client(factory, landlord, UserRole.Landlord);
        using var tenantClient = Client(factory, tenant, UserRole.Tenant);
        using var scope = factory.Services.CreateScope(); var db = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
        var property = new Property { LandlordId = landlord, Title = "Owned residence" };
        var offer = new RentalOffer { PropertyId = property.Id, TenantId = tenant, Status = RentalOfferStatus.Pending,
            ProposedStartDate = new DateOnly(2026, 1, 1), ProposedEndDate = new DateOnly(2027, 1, 1), ExpiresAt = DateTimeOffset.UtcNow.AddDays(1), MonthlyRent = 100 };
        db.AddRange(property, offer); await db.SaveChangesAsync();
        await new RentalOfferService(db, TimeProvider.System).AcceptAsync(offer.Id, tenant);
        var leaseService = new LeaseAgreementService(db);
        var lease = await leaseService.CreateAsync(new CreateLeaseAgreementDto { RentalOfferId = offer.Id });
        var schedule = new RentScheduleItem { LeaseAgreementId = lease.Id, Amount = 100, DueDate = new DateOnly(2026, 1, 1) };
        db.Add(schedule); await db.SaveChangesAsync();
        var paymentService = new PaymentService(db);
        var payment = await paymentService.CreateAsync(new CreatePaymentDto { RentScheduleItemId = schedule.Id, PaymentMethod = "BankTransfer" }, tenant);
        var events = await db.Notifications.Where(n => n.RecipientId == landlord).ToListAsync();
        Assert.Equal(3, events.Count);
        Assert.Contains(events, n => n.EventType == NotificationEventTypes.LeaseCreationRequired && n.RelatedResourceId == offer.Id);
        Assert.Contains(events, n => n.EventType == NotificationEventTypes.LeaseActivationRequired && n.RelatedResourceId == lease.Id);
        Assert.Contains(events, n => n.EventType == NotificationEventTypes.ManualPaymentReview && n.RelatedResourceId == payment.Id);
        Assert.All(events, n => Assert.DoesNotContain(n.RelatedResourceId.ToString(), n.Message));
        await leaseService.ActivateAsync(lease.Id); await paymentService.FailAsync(payment.Id);
        var summary = (await client.GetFromJsonAsync<LandlordActionSummary>("/api/landlord/actions/summary"))!;
        Assert.Equal(0, summary.LeaseCount); Assert.Equal(0, summary.PaymentCount);
        Assert.Equal(3, (await new NotificationService(db).GetUnreadCountAsync(landlord, CancellationToken.None)).UnreadCount);
    }
    [Fact]
    public async Task SummaryCountsOnlyActionableOwnedResourcesAndLatestCoordinationReview()
    {
        using var factory = new AuthApiFactory(); var landlord = Guid.NewGuid(); var other = Guid.NewGuid();
        using var client = Client(factory, landlord, UserRole.Landlord);
        var first = new Property { LandlordId = landlord, Title = "Port city residence" };
        var second = new Property { LandlordId = landlord, Title = "Harbour view" };
        var foreign = new Property { LandlordId = other, Title = "Not owned" };
        using (var scope = factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>(); db.AddRange(first, second, foreign);
            foreach (var status in Enum.GetValues<MaintenanceRequestStatus>()) db.MaintenanceRequests.Add(new MaintenanceRequest { PropertyId = first.Id, Status = status });
            db.MaintenanceRequests.Add(new MaintenanceRequest { PropertyId = second.Id, Status = MaintenanceRequestStatus.Submitted });
            db.MaintenanceRequests.Add(new MaintenanceRequest { PropertyId = foreign.Id, Status = MaintenanceRequestStatus.Submitted });
            var review = new MaintenanceRequest { PropertyId = second.Id, Status = MaintenanceRequestStatus.EstimatePending };
            var stale = new MaintenanceRequest { PropertyId = second.Id, Status = MaintenanceRequestStatus.InProgress };
            db.AddRange(review, stale);
            db.MaintenanceCoordinationWorkflows.AddRange(
                Review(review.Id, DateTimeOffset.UtcNow), Review(stale.Id, DateTimeOffset.UtcNow.AddDays(-1)),
                new MaintenanceCoordinationWorkflow { MaintenanceRequestId = stale.Id, Status = MaintenanceCoordinationWorkflowStatus.Completed, CreatedAt = DateTimeOffset.UtcNow });
            var accepted = new RentalOffer { PropertyId = first.Id, Status = RentalOfferStatus.Accepted };
            var withLease = new RentalOffer { PropertyId = first.Id, Status = RentalOfferStatus.Accepted };
            db.RentalOffers.AddRange(accepted, withLease, new RentalOffer { PropertyId = foreign.Id, Status = RentalOfferStatus.Accepted });
            foreach (var status in new[] { RentalOfferStatus.Pending, RentalOfferStatus.Rejected, RentalOfferStatus.Withdrawn, RentalOfferStatus.Expired }) db.RentalOffers.Add(new RentalOffer { PropertyId = first.Id, Status = status });
            var lease = new LeaseAgreement { PropertyId = first.Id, RentalOfferId = withLease.Id, Status = LeaseAgreementStatus.Pending };
            db.LeaseAgreements.Add(lease);
            foreach (var status in new[] { LeaseAgreementStatus.Active, LeaseAgreementStatus.Terminated, LeaseAgreementStatus.Completed }) db.LeaseAgreements.Add(new LeaseAgreement { PropertyId = first.Id, Status = status });
            var schedule = new RentScheduleItem { LeaseAgreement = lease, Amount = 100 };
            db.RentScheduleItems.Add(schedule);
            foreach (var status in Enum.GetValues<PaymentStatus>()) foreach (var provider in Enum.GetValues<PaymentProvider>())
                db.Payments.Add(new Payment { RentScheduleItem = schedule, Status = status, Provider = provider });
            await db.SaveChangesAsync();
        }
        var result = (await client.GetFromJsonAsync<LandlordActionSummary>($"/api/landlord/actions/summary?landlordId={other}"))!;
        Assert.Equal(6, result.MaintenanceCount); Assert.Equal(4, result.MaintenanceByProperty.Single(p => p.PropertyId == first.Id).Count);
        Assert.Equal(2, result.MaintenanceByProperty.Single(p => p.PropertyId == second.Id).Count);
        Assert.DoesNotContain(result.MaintenanceByProperty, p => p.PropertyId == foreign.Id);
        Assert.Equal(2, result.LeaseCount); Assert.Equal(1, result.PaymentCount);
        using var isolated = Client(factory, other, UserRole.Landlord);
        var otherResult = (await isolated.GetFromJsonAsync<LandlordActionSummary>("/api/landlord/actions/summary"))!;
        Assert.Equal(1, otherResult.MaintenanceCount); Assert.Equal(1, otherResult.LeaseCount); Assert.Equal(0, otherResult.PaymentCount);
    }

    [Fact]
    public async Task EmptySummaryAndAuthorizationAreTruthful()
    {
        using var factory = new AuthApiFactory(); using var anonymous = factory.CreateHttpsClient();
        Assert.Equal(HttpStatusCode.Unauthorized, (await anonymous.GetAsync("/api/landlord/actions/summary")).StatusCode);
        foreach (var role in new[] { UserRole.Tenant, UserRole.Admin, UserRole.MaintenanceTechnician })
        {
            using var denied = Client(factory, Guid.NewGuid(), role);
            Assert.Equal(HttpStatusCode.Forbidden, (await denied.GetAsync("/api/landlord/actions/summary")).StatusCode);
        }
        using var owner = Client(factory, Guid.NewGuid(), UserRole.Landlord);
        var summary = (await owner.GetFromJsonAsync<LandlordActionSummary>("/api/landlord/actions/summary"))!;
        Assert.Equal(0, summary.MaintenanceCount); Assert.Empty(summary.MaintenanceByProperty);
        Assert.Equal(0, summary.LeaseCount); Assert.Equal(0, summary.PaymentCount);
    }

    [Fact]
    public async Task OperationalNotificationsDeduplicateAndKeepBellIndependentOfActionCounts()
    {
        using var factory = new AuthApiFactory(); var landlord = Guid.NewGuid(); var other = Guid.NewGuid();
        using var owner = Client(factory, landlord, UserRole.Landlord); using var stranger = Client(factory, other, UserRole.Landlord);
        var property = new Property { LandlordId = landlord }; var source = Guid.NewGuid();
        using (var scope = factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>(); db.Add(property); await db.SaveChangesAsync();
            foreach (var type in new[] { NotificationEventTypes.MaintenanceSubmitted, NotificationEventTypes.LeaseCreationRequired, NotificationEventTypes.ManualPaymentReview })
            {
                await NotificationDeliveryPolicy.QueueLandlordActionAsync(db, property.Id, type, "MaintenanceRequest", source, source, "Review required", "An action is required for your property.", CancellationToken.None);
                await NotificationDeliveryPolicy.QueueLandlordActionAsync(db, property.Id, type, "MaintenanceRequest", source, source, "Review required", "An action is required for your property.", CancellationToken.None);
                await db.SaveChangesAsync();
                await NotificationDeliveryPolicy.QueueLandlordActionAsync(db, property.Id, type, "MaintenanceRequest", source, source, "Review required", "An action is required for your property.", CancellationToken.None);
            }
            await db.SaveChangesAsync();
            var notifications = await db.Notifications.ToListAsync(); Assert.Equal(3, notifications.Count);
            Assert.All(notifications, n => { Assert.Equal(landlord, n.RecipientId); Assert.DoesNotContain(source.ToString(), n.Message); });
            Assert.Equal(3, (await new NotificationService(db).GetUnreadCountAsync(landlord, CancellationToken.None)).UnreadCount);
            await new NotificationService(db).MarkAsReadAsync(landlord, notifications[0].Id, CancellationToken.None);
            Assert.Equal(2, (await new NotificationService(db).GetUnreadCountAsync(landlord, CancellationToken.None)).UnreadCount);
            Assert.Null(await new NotificationService(db).MarkAsReadAsync(other, notifications[1].Id, CancellationToken.None));
        }
        var summary = (await owner.GetFromJsonAsync<LandlordActionSummary>("/api/landlord/actions/summary"))!;
        Assert.Equal(0, summary.MaintenanceCount);
        Assert.Contains("\"unreadCount\":2", await owner.GetStringAsync("/api/notifications/unread-count"));
        Assert.Contains("\"unreadCount\":0", await stranger.GetStringAsync("/api/notifications/unread-count"));
    }

    private static MaintenanceCoordinationWorkflow Review(Guid request, DateTimeOffset date) => new() { MaintenanceRequestId = request, CreatedAt = date,
        Status = MaintenanceCoordinationWorkflowStatus.AwaitingHumanReview, ApprovalStatus = MaintenanceCoordinationApprovalStatus.Pending, RequiresHumanApproval = true };
    private static HttpClient Client(AuthApiFactory factory, Guid id, UserRole role)
    {
        factory.EnsureActiveUser(id, role); var client = factory.CreateHttpsClient();
        var token = new JwtSecurityToken(issuer: "RentFlow.Api.Tests", audience: "RentFlow.TestClients",
            claims: [new Claim(JwtRegisteredClaimNames.Sub, id.ToString()), new Claim("role", role.ToString()), new Claim("token_version", "0")],
            expires: DateTime.UtcNow.AddMinutes(10), signingCredentials: new SigningCredentials(new SymmetricSecurityKey(Encoding.UTF8.GetBytes("test-only-signing-key-that-is-at-least-32-bytes-long")), SecurityAlgorithms.HmacSha256));
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", new JwtSecurityTokenHandler().WriteToken(token)); return client;
    }
}
