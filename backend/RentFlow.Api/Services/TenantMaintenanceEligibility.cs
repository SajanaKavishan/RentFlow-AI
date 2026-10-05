using RentFlow.Api.Data;
using RentFlow.Api.Models;

namespace RentFlow.Api.Services;

/// <summary>The existing active-rental rule, shared by property lookup and creation.</summary>
public static class TenantMaintenanceEligibility
{
    public static IQueryable<Property> EligibleProperties(
        ApplicationDbContext context, Guid tenantId, DateOnly today) =>
        context.Properties.Where(property => context.LeaseAgreements.Any(lease =>
            lease.TenantId == tenantId
            && lease.PropertyId == property.Id
            && lease.Status == LeaseAgreementStatus.Active
            && lease.StartDate <= today
            && lease.EndDate >= today
            && context.RentalOffers.Any(offer =>
                offer.Id == lease.RentalOfferId
                && offer.Status == RentalOfferStatus.Accepted
                && offer.TenantId == lease.TenantId
                && offer.PropertyId == lease.PropertyId
                && context.RentalApplications.Any(application =>
                    application.Id == offer.RentalApplicationId
                    && application.Status == RentalApplicationStatus.Approved
                    && application.TenantId == lease.TenantId
                    && application.PropertyId == lease.PropertyId))));
}
