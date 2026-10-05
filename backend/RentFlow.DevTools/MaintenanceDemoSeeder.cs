using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Npgsql;
using RentFlow.Api.Data;
using RentFlow.Api.Models;

namespace RentFlow.DevTools;

public sealed class MaintenanceDemoSetupException(string message) : Exception(message);

public sealed record MaintenanceDemoResult(Guid PropertyId, string TenantEmail,
    IReadOnlyList<Guid> RequestIds, bool Created, string? NewTenantPassword);

/// <summary>Explicit local fixture creation; never used by the production API.</summary>
public static class MaintenanceDemoSeeder
{
    private const string Marker = "Synthetic maintenance AI fixture created by RentFlow.DevTools.";

    public static void ValidateLocalDevelopment(string connectionString, string? environment)
    {
        if (environment is not null && !environment.Equals("Development", StringComparison.OrdinalIgnoreCase))
            throw new MaintenanceDemoSetupException("Only Development is allowed; no staging/production fixture writes.");
        var connection = new NpgsqlConnectionStringBuilder(connectionString);
        if (connection.Host is not ("localhost" or "127.0.0.1" or "::1") || string.IsNullOrWhiteSpace(connection.Database))
            throw new MaintenanceDemoSetupException("This tool only supports a PostgreSQL database on localhost.");
        if (connection.Database.Contains("prod", StringComparison.OrdinalIgnoreCase))
            throw new MaintenanceDemoSetupException("Refusing a database named as production.");
    }

    public static async Task<MaintenanceDemoResult> CreateAsync(ApplicationDbContext db, string landlordEmail,
        DateTimeOffset now, bool dryRun, CancellationToken token = default)
    {
        if (string.IsNullOrWhiteSpace(landlordEmail)) throw new MaintenanceDemoSetupException("Provide a Landlord email.");
        var normalized = landlordEmail.Trim().ToUpperInvariant();
        var landlord = await db.Users.AsNoTracking().Where(user => user.NormalizedEmail == normalized)
            .Select(user => new { user.Id, user.Role, user.IsActive }).SingleOrDefaultAsync(token);
        if (landlord is null || landlord.Role != UserRole.Landlord || !landlord.IsActive)
            throw new MaintenanceDemoSetupException("No active Landlord matches that email in this development database.");
        var tenantEmail = $"maintenance-demo-{landlord.Id:N}@example.test";
        var property = await db.Properties.AsNoTracking()
            .SingleOrDefaultAsync(item => item.LandlordId == landlord.Id && item.Description == Marker, token);
        if (property is not null)
        {
            var ids = await db.MaintenanceRequests.AsNoTracking().Where(item => item.PropertyId == property.Id)
                .OrderBy(item => item.CreatedAt).Select(item => item.Id).ToListAsync(token);
            return new(property.Id, tenantEmail, ids, false, null);
        }
        if (await db.Users.AnyAsync(user => user.NormalizedEmail == tenantEmail.ToUpperInvariant(), token))
            throw new MaintenanceDemoSetupException("A fixture tenant already exists without its property. No users were changed.");
        if (dryRun) return new(Guid.Empty, tenantEmail, [], false, null);

        var password = "DevDemo1!" + Convert.ToHexString(System.Security.Cryptography.RandomNumberGenerator.GetBytes(24));
        var tenant = new ApplicationUser { Id = Guid.NewGuid(), FullName = "Maintenance Demo Tenant",
            Email = tenantEmail, NormalizedEmail = tenantEmail.ToUpperInvariant(), PhoneNumber = "+94770000000",
            Role = UserRole.Tenant, IsActive = true, CreatedAt = now, UpdatedAt = now };
        tenant.PasswordHash = new PasswordHasher<ApplicationUser>().HashPassword(tenant, password);
        property = new Property { LandlordId = landlord.Id, Title = "[DEV] Maintenance AI test apartment",
            Description = Marker, Address = "Development test address", City = "Colombo",
            MonthlyRent = 1000m, Bedrooms = 2, Bathrooms = 1, IsAvailable = false, CreatedAt = now };
        var today = DateOnly.FromDateTime(now.UtcDateTime);
        var application = new RentalApplication { PropertyId = property.Id, TenantId = tenant.Id,
            MoveInDate = today.AddDays(-1), MonthlyIncome = 5000m, Occupation = "Development test tenant",
            NumberOfOccupants = 1, Status = RentalApplicationStatus.Approved, CreatedAt = now, SubmittedAt = now };
        var offer = new RentalOffer { RentalApplicationId = application.Id, RentalApplication = application,
            TenantId = tenant.Id, PropertyId = property.Id, MonthlyRent = 1000m, SecurityDeposit = 1000m,
            ProposedStartDate = today.AddDays(-1), ProposedEndDate = today.AddDays(365),
            ExpiresAt = now.AddDays(7), Status = RentalOfferStatus.Accepted, CreatedAt = now };
        var lease = new LeaseAgreement { RentalOfferId = offer.Id, RentalOffer = offer,
            TenantId = tenant.Id, PropertyId = property.Id, MonthlyRent = 1000m, SecurityDeposit = 1000m,
            StartDate = offer.ProposedStartDate, EndDate = offer.ProposedEndDate,
            Status = LeaseAgreementStatus.Active, CreatedAt = now };
        var requests = new[] {
            NewRequest(property.Id, tenant.Id, now, "[DEV] Leaking kitchen sink",
                "Water drips from the pipe beneath the kitchen sink whenever the tap is running. The source is visible but has not been inspected by a technician.", MaintenanceCategory.Plumbing),
            NewRequest(property.Id, tenant.Id, now.AddSeconds(1), "[DEV] Air conditioner blows warm air",
                "The bedroom air conditioner turns on but blows warm air. The filter has been cleaned. A technician needs to check the unit and confirm the cause.", MaintenanceCategory.Hvac),
        };
        db.Users.Add(tenant);
        db.Properties.Add(property);
        db.RentalApplications.Add(application);
        db.RentalOffers.Add(offer);
        db.LeaseAgreements.Add(lease);
        db.MaintenanceRequests.AddRange(requests);
        db.MaintenanceStatusHistories.AddRange(requests.Select(request => new MaintenanceStatusHistory {
            MaintenanceRequestId = request.Id, ToStatus = MaintenanceRequestStatus.Submitted,
            ChangedByUserId = tenant.Id, ChangedAt = request.CreatedAt, Notes = "Development test request created." }));
        await db.SaveChangesAsync(token);
        return new(property.Id, tenant.Email, requests.Select(item => item.Id).ToArray(), true, password);
    }

    private static MaintenanceRequest NewRequest(Guid propertyId, Guid tenantId, DateTimeOffset now,
        string title, string description, MaintenanceCategory category)
    {
        var id = Guid.NewGuid();
        return new MaintenanceRequest { Id = id, ReferenceCode = "MR-" + id.ToString("N")[..16].ToUpperInvariant(),
            PropertyId = propertyId, TenantId = tenantId, Title = title, Description = description,
            Category = category, Priority = MaintenancePriority.Normal, Status = MaintenanceRequestStatus.Submitted,
            PreferredAccessWindow = PreferredAccessWindow.Morning, CreatedAt = now };
    }
}
