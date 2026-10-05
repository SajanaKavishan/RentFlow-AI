using Microsoft.EntityFrameworkCore;
using RentFlow.Api.Data;
using RentFlow.Api.DTOs.PricingAnalysis;
using RentFlow.Api.Models;
using RentFlow.Api.Services.Interfaces;

namespace RentFlow.Api.Services;

public sealed class PricingComparableRentalsTool(ApplicationDbContext dbContext)
    : IPricingComparableRentalsTool
{
    public async Task<IReadOnlyCollection<PricingComparableEvidence>> GetAsync(
        PricingEvidenceScope subject,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(subject);
        cancellationToken.ThrowIfCancellationRequested();

        if (subject.SubjectPropertyId == Guid.Empty
            || subject.SubjectLandlordId == Guid.Empty
            || subject.SubjectFacts.PropertyId != subject.SubjectPropertyId)
        {
            return Array.Empty<PricingComparableEvidence>();
        }

        var cityKey = NormalizeCity(subject.SubjectFacts.City);
        if (cityKey.Length == 0)
        {
            return Array.Empty<PricingComparableEvidence>();
        }

        var properties = await dbContext.Properties
            .AsNoTracking()
            .Where(property => property.Id != subject.SubjectPropertyId
                && property.Bedrooms >= Math.Max(0, subject.SubjectFacts.Bedrooms - 1)
                && property.Bedrooms <= subject.SubjectFacts.Bedrooms + 1
                && property.Bathrooms >= Math.Max(0, subject.SubjectFacts.Bathrooms - 1)
                && property.Bathrooms <= subject.SubjectFacts.Bathrooms + 1)
            .ToListAsync(cancellationToken);

        var relevantProperties = properties
            .Where(property => NormalizeCity(property.City) == cityKey)
            .ToDictionary(property => property.Id);
        if (relevantProperties.Count == 0)
        {
            return Array.Empty<PricingComparableEvidence>();
        }

        var propertyIds = relevantProperties.Keys.ToArray();
        var leases = await dbContext.LeaseAgreements
            .AsNoTracking()
            .Where(lease => propertyIds.Contains(lease.PropertyId)
                && (lease.Status == LeaseAgreementStatus.Active
                    || lease.Status == LeaseAgreementStatus.Completed))
            .ToListAsync(cancellationToken);

        var offers = await dbContext.RentalOffers
            .AsNoTracking()
            .Where(offer => propertyIds.Contains(offer.PropertyId)
                && offer.Status == RentalOfferStatus.Accepted)
            .ToListAsync(cancellationToken);

        var qualifyingLeaseByProperty = leases
            .GroupBy(lease => lease.PropertyId)
            .ToDictionary(
                group => group.Key,
                group => group.OrderByDescending(lease => lease.StartDate).First());
        var qualifyingLeaseOfferIds = leases.Select(lease => lease.RentalOfferId).ToHashSet();
        var acceptedOfferByProperty = offers
            .Where(offer => !qualifyingLeaseOfferIds.Contains(offer.Id))
            .GroupBy(offer => offer.PropertyId)
            .ToDictionary(
                group => group.Key,
                group => group.OrderByDescending(offer => offer.UpdatedAt ?? offer.CreatedAt).First());

        var selected = new List<SelectedEvidence>();
        foreach (var property in relevantProperties.Values)
        {
            if (qualifyingLeaseByProperty.TryGetValue(property.Id, out var lease))
            {
                selected.Add(new SelectedEvidence(
                    property,
                    PricingEvidenceSourceType.LEASE_AGREED_RENT,
                    lease.MonthlyRent,
                    lease.Status.ToString(),
                    new DateTimeOffset(lease.StartDate.ToDateTime(TimeOnly.MinValue), TimeSpan.Zero),
                    PricingEvidenceStrength.HIGH));
                continue;
            }

            if (acceptedOfferByProperty.TryGetValue(property.Id, out var offer))
            {
                selected.Add(new SelectedEvidence(
                    property,
                    PricingEvidenceSourceType.RENTAL_OFFER,
                    offer.MonthlyRent,
                    offer.Status.ToString(),
                    offer.UpdatedAt ?? offer.CreatedAt,
                    PricingEvidenceStrength.MEDIUM));
                continue;
            }

            if (property.IsAvailable)
            {
                selected.Add(new SelectedEvidence(
                    property,
                    PricingEvidenceSourceType.LISTING_ASKING_RENT,
                    property.MonthlyRent,
                    "Available",
                    property.UpdatedAt ?? property.CreatedAt,
                    PricingEvidenceStrength.LOW));
            }
        }

        return selected
            .OrderBy(item => item.Property.Id)
            .Select((item, index) => new PricingComparableEvidence
            {
                EvidenceRef = $"cmp-{index + 1:000}",
                SourceType = item.SourceType,
                MonthlyRent = item.MonthlyRent,
                City = item.Property.City,
                Bedrooms = item.Property.Bedrooms,
                Bathrooms = item.Property.Bathrooms,
                SourceStatus = item.SourceStatus,
                EvidenceDate = item.EvidenceDate,
                EvidenceStrength = item.EvidenceStrength
            })
            .ToArray();
    }

    private static string NormalizeCity(string? city) =>
        string.IsNullOrWhiteSpace(city) ? string.Empty : city.Trim().ToUpperInvariant();

    private sealed record SelectedEvidence(
        Property Property,
        PricingEvidenceSourceType SourceType,
        decimal MonthlyRent,
        string SourceStatus,
        DateTimeOffset EvidenceDate,
        PricingEvidenceStrength EvidenceStrength);
}
