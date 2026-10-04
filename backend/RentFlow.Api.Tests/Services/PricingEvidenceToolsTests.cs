using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using RentFlow.Api.Data;
using RentFlow.Api.DTOs.PricingAnalysis;
using RentFlow.Api.Models;
using RentFlow.Api.Services;
using Xunit;

namespace RentFlow.Api.Tests.Services;

public sealed class PricingEvidenceToolsTests
{
    private static readonly DateTimeOffset Now =
        new(2026, 9, 25, 8, 0, 0, TimeSpan.Zero);

    [Fact]
    public async Task PropertyFacts_ReturnOnlyApprovedSnapshotFields()
    {
        await using var context = CreateContext();
        var property = CreateProperty();
        property.Title = "Private title";
        property.Description = "Private description";
        property.Address = "Private address";
        property.Amenities.Add(new PropertyAmenity { PropertyId = property.Id, Name = "Pool" });
        context.Properties.Add(property);
        await context.SaveChangesAsync();

        var facts = await new PricingPropertyFactsTool(context, new FixedTimeProvider(Now))
            .GetAsync(property.Id);

        Assert.NotNull(facts);
        Assert.Equal(property.Id, facts.SubjectFacts.PropertyId);
        Assert.Equal(property.City, facts.SubjectFacts.City);
        Assert.Equal(property.MonthlyRent, facts.SubjectFacts.MonthlyRent);
        Assert.Equal(property.Bedrooms, facts.SubjectFacts.Bedrooms);
        Assert.Equal(property.Bathrooms, facts.SubjectFacts.Bathrooms);
        Assert.Equal(property.IsAvailable, facts.SubjectFacts.IsAvailable);
        Assert.Equal(Now, facts.SubjectFacts.SnapshotAt);
        Assert.Equal(
            new[] { "PropertyId", "City", "MonthlyRent", "Bedrooms", "Bathrooms", "IsAvailable", "SnapshotAt" },
            typeof(PricingPropertyFacts).GetProperties().Select(propertyInfo => propertyInfo.Name).ToArray());
    }

    [Fact]
    public async Task PropertyFacts_ReturnNullForMissingOrEmptyIdentifier()
    {
        await using var context = CreateContext();
        var tool = new PricingPropertyFactsTool(context, new FixedTimeProvider(Now));

        Assert.Null(await tool.GetAsync(Guid.Empty));
        Assert.Null(await tool.GetAsync(Guid.NewGuid()));
    }

    [Fact]
    public async Task Comparables_ExcludeSubjectAndUnrelatedPropertiesButAllowNearbyRoomsAndOtherOwners()
    {
        await using var context = CreateContext();
        var owner = Guid.NewGuid();
        var subject = CreateProperty(owner, city: " Colombo ");
        var matching = CreateProperty(owner, city: "colombo", available: true);
        var otherOwner = CreateProperty(Guid.NewGuid(), available: true);
        var subjectDuplicate = CreateProperty(owner, available: true);
        var otherCity = CreateProperty(owner, city: "Kandy");
        var otherBedrooms = CreateProperty(owner, bedrooms: 3, available: true);
        var otherBathrooms = CreateProperty(owner, bathrooms: 2, available: true);
        var unrelatedRooms = CreateProperty(owner, bedrooms: 4, bathrooms: 4);
        context.Properties.AddRange(subject, matching, otherOwner, subjectDuplicate, otherCity, otherBedrooms, otherBathrooms, unrelatedRooms);
        await context.SaveChangesAsync();

        var evidence = await GetEvidence(context, subject);

        Assert.Equal(5, evidence.Count);
        Assert.All(evidence, item => Assert.Equal("Colombo", item.City, ignoreCase: true));
        Assert.Equal(evidence.Count, evidence.Select(item => item.EvidenceRef).Distinct().Count());
    }

    [Fact]
    public async Task GoldenColomboSet_ReturnsSimilarEvidenceBeforeAgentAnalysis()
    {
        await using var context = CreateContext();
        var owner = Guid.NewGuid();
        var subject = CreateProperty(owner, bedrooms: 2, bathrooms: 2, available: true);
        subject.MonthlyRent = 90000m;
        subject.Area = 1000m;
        subject.AreaUnit = "sqft";
        var comparableFacts = new (int Beds, int Baths, decimal Area, decimal Rent)[]
        {
            (2, 2, 950m, 120000m), (2, 2, 1050m, 135000m),
            (2, 2, 1100m, 155000m), (2, 1, 850m, 100000m)
        };
        var comparables = comparableFacts.Select((item, index) =>
        {
            var property = CreateProperty(index % 2 == 0 ? Guid.NewGuid() : owner,
                bedrooms: item.Beds, bathrooms: item.Baths, available: true);
            property.Area = item.Area;
            property.AreaUnit = "sqft";
            property.MonthlyRent = item.Rent;
            return property;
        }).ToArray();
        context.Properties.AddRange([subject, .. comparables]);
        await context.SaveChangesAsync();

        var evidence = await GetEvidence(context, subject);
        var assessment = new PricingEvidenceAssessmentTool().Assess(evidence);

        Assert.Equal(4, evidence.Count);
        Assert.Equal(PricingEvidenceSufficiency.LIMITED, assessment.EvidenceSufficiency);
        Assert.Equal(evidence.Count, assessment.UsableEvidenceCount);
    }

    [Theory]
    [InlineData(true, 1)]
    [InlineData(false, 0)]
    public async Task Listing_IsIncludedOnlyWhenAvailable(bool available, int expectedCount)
    {
        await using var context = CreateContext();
        var subject = CreateProperty();
        var comparable = CreateProperty(subject.LandlordId, available: available);
        context.Properties.AddRange(subject, comparable);
        await context.SaveChangesAsync();

        var evidence = await GetEvidence(context, subject);

        Assert.Equal(expectedCount, evidence.Count);
        if (expectedCount == 1)
        {
            Assert.Equal(PricingEvidenceSourceType.LISTING_ASKING_RENT, evidence.Single().SourceType);
            Assert.Equal(PricingEvidenceStrength.LOW, evidence.Single().EvidenceStrength);
            Assert.Equal("Available", evidence.Single().SourceStatus);
        }
    }

    [Theory]
    [InlineData(RentalOfferStatus.Accepted, 1)]
    [InlineData(RentalOfferStatus.Pending, 0)]
    [InlineData(RentalOfferStatus.Rejected, 0)]
    [InlineData(RentalOfferStatus.Withdrawn, 0)]
    [InlineData(RentalOfferStatus.Expired, 0)]
    public async Task OfferEligibility_OnlyAcceptedOffersQualify(RentalOfferStatus status, int expectedCount)
    {
        await using var context = CreateContext();
        var subject = CreateProperty();
        var comparable = CreateProperty(subject.LandlordId, available: false);
        context.Properties.AddRange(subject, comparable);
        context.RentalOffers.Add(CreateOffer(comparable, status));
        await context.SaveChangesAsync();

        var evidence = await GetEvidence(context, subject);

        Assert.Equal(expectedCount, evidence.Count);
        if (expectedCount == 1)
        {
            Assert.Equal(PricingEvidenceSourceType.RENTAL_OFFER, evidence.Single().SourceType);
            Assert.Equal(PricingEvidenceStrength.MEDIUM, evidence.Single().EvidenceStrength);
        }
    }

    [Theory]
    [InlineData(LeaseAgreementStatus.Active, 1)]
    [InlineData(LeaseAgreementStatus.Completed, 1)]
    [InlineData(LeaseAgreementStatus.Pending, 0)]
    [InlineData(LeaseAgreementStatus.Terminated, 0)]
    public async Task LeaseEligibility_OnlyActiveAndCompletedQualify(LeaseAgreementStatus status, int expectedCount)
    {
        await using var context = CreateContext();
        var subject = CreateProperty();
        var comparable = CreateProperty(subject.LandlordId, available: false);
        context.Properties.AddRange(subject, comparable);
        var lease = CreateLease(comparable, status, new DateOnly(2025, 4, 1));
        context.LeaseAgreements.Add(lease);
        await context.SaveChangesAsync();

        var evidence = await GetEvidence(context, subject);

        Assert.Equal(expectedCount, evidence.Count);
        if (expectedCount == 1)
        {
            Assert.Equal(PricingEvidenceSourceType.LEASE_AGREED_RENT, evidence.Single().SourceType);
            Assert.Equal(PricingEvidenceStrength.HIGH, evidence.Single().EvidenceStrength);
            Assert.Equal(new DateTimeOffset(2025, 4, 1, 0, 0, 0, TimeSpan.Zero), evidence.Single().EvidenceDate);
        }
    }

    [Fact]
    public async Task LeasePrecedesOfferAndListing_UsesMostRecentLeaseAndHidesIdentifiers()
    {
        await using var context = CreateContext();
        var subject = CreateProperty();
        var comparable = CreateProperty(subject.LandlordId, available: true);
        context.Properties.AddRange(subject, comparable);
        var offer = CreateOffer(comparable, RentalOfferStatus.Accepted);
        context.RentalOffers.Add(offer);
        context.LeaseAgreements.AddRange(
            CreateLease(comparable, LeaseAgreementStatus.Completed, new DateOnly(2024, 1, 1), offer.Id, 111000m),
            CreateLease(comparable, LeaseAgreementStatus.Active, new DateOnly(2025, 1, 1), offer.Id, 123000m));
        await context.SaveChangesAsync();

        var evidence = (await GetEvidence(context, subject)).Single();
        var serialized = JsonSerializer.Serialize(
            evidence,
            new JsonSerializerOptions(JsonSerializerDefaults.Web));

        Assert.Equal(PricingEvidenceSourceType.LEASE_AGREED_RENT, evidence.SourceType);
        Assert.Equal(123000m, evidence.MonthlyRent);
        Assert.DoesNotContain(comparable.Id.ToString(), serialized);
        Assert.DoesNotContain(offer.Id.ToString(), serialized);
        Assert.DoesNotContain("TenantId", serialized);
        Assert.DoesNotContain("LandlordId", serialized);
        Assert.DoesNotContain("PropertyId", serialized);
        Assert.Contains("\"sourceType\":\"LEASE_AGREED_RENT\"", serialized);
        Assert.Equal("cmp-001", evidence.EvidenceRef);
    }

    [Fact]
    public async Task AcceptedOfferPrecedesListing_WhenNoQualifyingLeaseExists()
    {
        await using var context = CreateContext();
        var subject = CreateProperty();
        var comparable = CreateProperty(subject.LandlordId, available: true);
        context.Properties.AddRange(subject, comparable);
        context.RentalOffers.Add(CreateOffer(comparable, RentalOfferStatus.Accepted));
        await context.SaveChangesAsync();

        var evidence = (await GetEvidence(context, subject)).Single();

        Assert.Equal(PricingEvidenceSourceType.RENTAL_OFFER, evidence.SourceType);
        Assert.Equal("Accepted", evidence.SourceStatus);
        Assert.Equal(Now.AddDays(-1), evidence.EvidenceDate);
    }

    [Fact]
    public async Task MultipleAcceptedOffersAndLeases_StillProduceOneObservationPerProperty()
    {
        await using var context = CreateContext();
        var subject = CreateProperty();
        var comparable = CreateProperty(subject.LandlordId);
        context.Properties.AddRange(subject, comparable);
        context.RentalOffers.AddRange(
            CreateOffer(comparable, RentalOfferStatus.Accepted, Now.AddDays(-2)),
            CreateOffer(comparable, RentalOfferStatus.Accepted, Now.AddDays(-1)));
        await context.SaveChangesAsync();

        var evidence = await GetEvidence(context, subject);

        Assert.Single(evidence);
        Assert.Equal("cmp-001", evidence.Single().EvidenceRef);
    }

    [Fact]
    public void Assessment_ZeroOneAndTwoObservationsHaveExpectedSufficiencyAndConfidence()
    {
        var tool = new PricingEvidenceAssessmentTool();

        var zero = tool.Assess([]);
        var one = tool.Assess([Evidence(PricingEvidenceSourceType.LEASE_AGREED_RENT)]);
        var two = tool.Assess([
            Evidence(PricingEvidenceSourceType.LEASE_AGREED_RENT),
            Evidence(PricingEvidenceSourceType.RENTAL_OFFER)]);

        AssertAssessment(zero, PricingEvidenceSufficiency.INSUFFICIENT, PricingConfidence.LOW, false);
        AssertAssessment(one, PricingEvidenceSufficiency.LIMITED, PricingConfidence.LOW, true);
        AssertAssessment(two, PricingEvidenceSufficiency.LIMITED, PricingConfidence.LOW, true);
    }

    [Fact]
    public void Assessment_AskingOnlyRemainsLimitedRegardlessOfCount()
    {
        var result = new PricingEvidenceAssessmentTool().Assess(
            Enumerable.Range(0, 8)
                .Select(_ => Evidence(PricingEvidenceSourceType.LISTING_ASKING_RENT))
                .ToArray());

        AssertAssessment(result, PricingEvidenceSufficiency.LIMITED, PricingConfidence.LOW, true);
        Assert.Equal(8, result.SourceCounts.ListingAskingRent);
        Assert.Contains(result.Limitations, limitation => limitation.Contains("asking rents", StringComparison.OrdinalIgnoreCase));
    }

    [Fact]
    public void Assessment_ThreeWithLeaseIsModerate_AndFiveWithThreeLeasesIsStrong()
    {
        var tool = new PricingEvidenceAssessmentTool();
        var moderate = tool.Assess([
            Evidence(PricingEvidenceSourceType.LEASE_AGREED_RENT),
            Evidence(PricingEvidenceSourceType.RENTAL_OFFER),
            Evidence(PricingEvidenceSourceType.LISTING_ASKING_RENT)]);
        var strong = tool.Assess([
            Evidence(PricingEvidenceSourceType.LEASE_AGREED_RENT),
            Evidence(PricingEvidenceSourceType.LEASE_AGREED_RENT),
            Evidence(PricingEvidenceSourceType.LEASE_AGREED_RENT),
            Evidence(PricingEvidenceSourceType.RENTAL_OFFER),
            Evidence(PricingEvidenceSourceType.LISTING_ASKING_RENT)]);

        AssertAssessment(moderate, PricingEvidenceSufficiency.MODERATE, PricingConfidence.MEDIUM, true);
        AssertAssessment(strong, PricingEvidenceSufficiency.STRONG, PricingConfidence.MEDIUM, true);
        Assert.Equal(1, moderate.SourceCounts.LeaseAgreedRent);
    }

    [Fact]
    public void Assessment_NeverAssignsHighConfidence()
    {
        var tool = new PricingEvidenceAssessmentTool();
        foreach (var count in new[] { 0, 1, 3, 5, 12 })
        {
            var evidence = Enumerable.Range(0, count)
                .Select(index => Evidence(index < 5
                    ? PricingEvidenceSourceType.LEASE_AGREED_RENT
                    : PricingEvidenceSourceType.RENTAL_OFFER))
                .ToArray();

            Assert.NotEqual(PricingConfidence.HIGH, tool.Assess(evidence).Confidence);
        }
    }

    [Fact]
    public void Assessment_CountsSourcesAndRequiresLeaseForModerate()
    {
        var result = new PricingEvidenceAssessmentTool().Assess([
            Evidence(PricingEvidenceSourceType.RENTAL_OFFER),
            Evidence(PricingEvidenceSourceType.RENTAL_OFFER),
            Evidence(PricingEvidenceSourceType.LISTING_ASKING_RENT)]);

        AssertAssessment(result, PricingEvidenceSufficiency.LIMITED, PricingConfidence.LOW, true);
        Assert.Equal(2, result.SourceCounts.RentalOffer);
        Assert.Equal(1, result.SourceCounts.ListingAskingRent);
        Assert.Equal(0, result.SourceCounts.LeaseAgreedRent);
    }

    private static void AssertAssessment(
        PricingDeterministicAssessment result,
        PricingEvidenceSufficiency sufficiency,
        PricingConfidence confidence,
        bool recommendationAllowed)
    {
        Assert.Equal(sufficiency, result.EvidenceSufficiency);
        Assert.Equal(confidence, result.Confidence);
        Assert.Equal(recommendationAllowed, result.NumericalRecommendationAllowed);
    }

    private static PricingComparableEvidence Evidence(PricingEvidenceSourceType source) => new()
    {
        EvidenceRef = Guid.NewGuid().ToString("N"),
        SourceType = source
    };

    private static async Task<IReadOnlyCollection<PricingComparableEvidence>> GetEvidence(
        ApplicationDbContext context,
        Property subject)
    {
        var scope = new PricingEvidenceScope
        {
            SubjectPropertyId = subject.Id,
            SubjectLandlordId = subject.LandlordId,
            SubjectFacts = Facts(subject)
        };
        return await new PricingComparableRentalsTool(context).GetAsync(scope);
    }

    private static PricingPropertyFacts Facts(Property property) => new()
    {
        PropertyId = property.Id,
        City = property.City,
        MonthlyRent = property.MonthlyRent,
        Bedrooms = property.Bedrooms,
        Bathrooms = property.Bathrooms,
        IsAvailable = property.IsAvailable,
        SnapshotAt = Now
    };

    private static Property CreateProperty(
        Guid? landlordId = null,
        string city = "Colombo",
        int bedrooms = 2,
        int bathrooms = 1,
        bool available = false) => new()
    {
        LandlordId = landlordId ?? Guid.NewGuid(),
        Title = "Test Property",
        Description = "Test description",
        Address = "Test address",
        City = city,
        MonthlyRent = 100000m,
        Bedrooms = bedrooms,
        Bathrooms = bathrooms,
        IsAvailable = available,
        CreatedAt = Now.AddDays(-30)
    };

    private static RentalOffer CreateOffer(
        Property property,
        RentalOfferStatus status,
        DateTimeOffset? createdAt = null)
    {
        var timestamp = createdAt ?? Now.AddDays(-2);
        return new RentalOffer
        {
            PropertyId = property.Id,
            RentalApplicationId = Guid.NewGuid(),
            TenantId = Guid.NewGuid(),
            MonthlyRent = 110000m,
            SecurityDeposit = 100000m,
            ProposedStartDate = new DateOnly(2026, 10, 1),
            ProposedEndDate = new DateOnly(2027, 9, 30),
            ExpiresAt = Now.AddDays(10),
            Status = status,
            CreatedAt = timestamp,
            UpdatedAt = status == RentalOfferStatus.Accepted ? timestamp.AddDays(1) : null
        };
    }

    private static LeaseAgreement CreateLease(
        Property property,
        LeaseAgreementStatus status,
        DateOnly startDate,
        Guid? offerId = null,
        decimal monthlyRent = 120000m) => new()
    {
        RentalOfferId = offerId ?? Guid.NewGuid(),
        TenantId = Guid.NewGuid(),
        PropertyId = property.Id,
        MonthlyRent = monthlyRent,
        SecurityDeposit = 100000m,
        StartDate = startDate,
        EndDate = startDate.AddYears(1),
        Status = status,
        CreatedAt = Now.AddDays(-20)
    };

    private static ApplicationDbContext CreateContext() => new(
        new DbContextOptionsBuilder<ApplicationDbContext>()
            .UseInMemoryDatabase($"PricingEvidence-{Guid.NewGuid()}")
            .Options);

    private sealed class FixedTimeProvider(DateTimeOffset now) : TimeProvider
    {
        public override DateTimeOffset GetUtcNow() => now;
    }
}
