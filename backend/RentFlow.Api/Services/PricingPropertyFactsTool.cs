using Microsoft.EntityFrameworkCore;
using RentFlow.Api.Data;
using RentFlow.Api.DTOs.PricingAnalysis;
using RentFlow.Api.Services.Interfaces;

namespace RentFlow.Api.Services;

public sealed class PricingPropertyFactsTool(
    ApplicationDbContext dbContext,
    TimeProvider timeProvider) : IPricingPropertyFactsTool
{
    public async Task<PricingEvidenceScope?> GetAsync(
        Guid propertyId,
        CancellationToken cancellationToken = default)
    {
        if (propertyId == Guid.Empty)
        {
            return null;
        }

        var property = await dbContext.Properties
            .AsNoTracking()
            .SingleOrDefaultAsync(item => item.Id == propertyId, cancellationToken);

        if (property is null)
        {
            return null;
        }

        return new PricingEvidenceScope
        {
            SubjectPropertyId = property.Id,
            SubjectLandlordId = property.LandlordId,
            SubjectFacts = new PricingPropertyFacts
            {
                PropertyId = property.Id,
                City = property.City,
                MonthlyRent = property.MonthlyRent,
                Bedrooms = property.Bedrooms,
                Bathrooms = property.Bathrooms,
                IsAvailable = property.IsAvailable,
                SnapshotAt = timeProvider.GetUtcNow()
            }
        };
    }
}
