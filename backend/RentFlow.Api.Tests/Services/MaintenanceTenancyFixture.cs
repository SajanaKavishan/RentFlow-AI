using Microsoft.EntityFrameworkCore;
using RentFlow.Api.Data;
using RentFlow.Api.Models;

namespace RentFlow.Api.Tests.Services;

internal static class MaintenanceTenancyFixture
{
    internal static async Task<LeaseAgreement> SeedAsync(ApplicationDbContext context, Guid tenantId, Guid propertyId, LeaseAgreementStatus status = LeaseAgreementStatus.Active)
    {
        var landlordId = Guid.NewGuid();
        if (!await context.Users.AnyAsync(user => user.Id == tenantId)) context.Users.Add(User(tenantId, UserRole.Tenant));
        context.Users.Add(User(landlordId, UserRole.Landlord));
        var today = DateOnly.FromDateTime(DateTime.UtcNow);
        var property = new Property { Id = propertyId, LandlordId = landlordId, Title = "Occupied test home", Description = "Test home", Address = "12 Test Road", City = "Colombo", MonthlyRent = 100000m, Bedrooms = 2, Bathrooms = 1, IsAvailable = false };
        var application = new RentalApplication { TenantId = tenantId, PropertyId = propertyId, Status = RentalApplicationStatus.Approved, MoveInDate = today.AddDays(-1), MonthlyIncome = 200000m, Occupation = "Test", NumberOfOccupants = 1 };
        var offer = new RentalOffer { RentalApplication = application, RentalApplicationId = application.Id, TenantId = tenantId, PropertyId = propertyId, Status = RentalOfferStatus.Accepted, MonthlyRent = property.MonthlyRent, SecurityDeposit = 100000m, ProposedStartDate = today.AddDays(-1), ProposedEndDate = today.AddDays(30), ExpiresAt = DateTimeOffset.UtcNow.AddDays(7) };
        var lease = new LeaseAgreement { RentalOffer = offer, RentalOfferId = offer.Id, TenantId = tenantId, PropertyId = propertyId, StartDate = offer.ProposedStartDate, EndDate = offer.ProposedEndDate, MonthlyRent = offer.MonthlyRent, SecurityDeposit = offer.SecurityDeposit, Status = status };
        context.Properties.Add(property);
        context.RentalApplications.Add(application);
        context.RentalOffers.Add(offer);
        context.LeaseAgreements.Add(lease);
        await context.SaveChangesAsync();
        return lease;
    }

    private static ApplicationUser User(Guid id, UserRole role) => new() { Id = id, FullName = "Maintenance Test User", Email = $"{id:N}@test.invalid", NormalizedEmail = $"{id:N}@TEST.INVALID", PhoneNumber = "+94770000000", PasswordHash = "test-only", Role = role, IsActive = true };
}
