using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using RentFlow.Api.Data;
using RentFlow.Api.Models;
using RentFlow.Api.Services.Interfaces;

namespace RentFlow.Api.Controllers;

[ApiController, Authorize(Roles = nameof(UserRole.Landlord))]
[Route("api/landlord/actions/summary")]
public sealed class LandlordActionsController(ApplicationDbContext db, ICurrentUserService actor) : ControllerBase
{
    [HttpGet]
    public async Task<ActionResult<LandlordActionSummary>> Get(CancellationToken ct)
    {
        if (actor.UserId is not Guid landlord) return Unauthorized();
        var owned = db.Properties.Where(p => p.LandlordId == landlord).Select(p => p.Id);
        var maintenance = await db.MaintenanceRequests.AsNoTracking().Where(r => owned.Contains(r.PropertyId) &&
            r.Status != MaintenanceRequestStatus.Completed && r.Status != MaintenanceRequestStatus.Rejected && r.Status != MaintenanceRequestStatus.Cancelled &&
            (r.Status == MaintenanceRequestStatus.Submitted || r.Status == MaintenanceRequestStatus.Triaged ||
             r.Status == MaintenanceRequestStatus.Assigned || r.Status == MaintenanceRequestStatus.AwaitingLandlordApproval ||
             db.MaintenanceCoordinationWorkflows.Where(w => w.MaintenanceRequestId == r.Id).OrderByDescending(w => w.CreatedAt).ThenByDescending(w => w.Id)
                .Select(w => w.Status == MaintenanceCoordinationWorkflowStatus.AwaitingHumanReview && w.RequiresHumanApproval && w.ApprovalStatus == MaintenanceCoordinationApprovalStatus.Pending).FirstOrDefault()))
            .GroupBy(r => r.PropertyId).Select(group => new PropertyActionCount(group.Key, group.Count())).ToListAsync(ct);
        var offers = await db.RentalOffers.CountAsync(o => owned.Contains(o.PropertyId) && o.Status == RentalOfferStatus.Accepted &&
            !db.LeaseAgreements.Any(l => l.RentalOfferId == o.Id), ct);
        var leases = await db.LeaseAgreements.CountAsync(l => owned.Contains(l.PropertyId) && l.Status == LeaseAgreementStatus.Pending, ct);
        var payments = await db.Payments.CountAsync(p => owned.Contains(p.RentScheduleItem.LeaseAgreement.PropertyId) &&
            p.Provider == PaymentProvider.Manual && p.Status == PaymentStatus.Pending, ct);
        Response.Headers.CacheControl = "private, no-store";
        return Ok(new LandlordActionSummary(maintenance.Sum(item => item.Count), maintenance, offers + leases, payments));
    }
}

public sealed record PropertyActionCount(Guid PropertyId, int Count);
public sealed record LandlordActionSummary(int MaintenanceCount, IReadOnlyList<PropertyActionCount> MaintenanceByProperty, int LeaseCount, int PaymentCount);
