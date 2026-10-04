using Microsoft.EntityFrameworkCore;
using RentFlow.Api.Data;
using RentFlow.Api.DTOs.ViewingReviews;
using RentFlow.Api.Models;
using RentFlow.Api.Services;
using Xunit;

namespace RentFlow.Api.Tests.Services;

public sealed class ViewingReviewTests
{
    private static readonly DateTimeOffset Now = new(2030, 1, 2, 10, 0, 0, TimeSpan.Zero);
    private static ApplicationDbContext Context() => new(new DbContextOptionsBuilder<ApplicationDbContext>().UseInMemoryDatabase(Guid.NewGuid().ToString()).Options);
    private static SaveViewingReviewDto Input(int? property = 4, int? landlord = 5, string? comment = "  Honest viewing experience  ") => new() { PropertyRating = property, LandlordRating = landlord, Comment = comment };
    private static async Task<(Guid Tenant, Property Property, ViewingRequest Viewing)> Seed(ApplicationDbContext db, ViewingStatus status = ViewingStatus.Completed)
    {
        var tenant = Guid.NewGuid(); var landlord = new ApplicationUser { Id = Guid.NewGuid(), Role = UserRole.Landlord, IsActive = true };
        var property = new Property { LandlordId = landlord.Id, Landlord = landlord, Title = "Viewed home", IsAvailable = true };
        var viewing = new ViewingRequest { TenantId = tenant, PropertyId = property.Id, Status = status, RequestedDateTime = Now.AddDays(-1) };
        db.AddRange(landlord, property, viewing); await db.SaveChangesAsync(); return (tenant, property, viewing);
    }
    [Theory]
    [InlineData(ViewingStatus.Pending)] [InlineData(ViewingStatus.Approved)] [InlineData(ViewingStatus.Cancelled)] [InlineData(ViewingStatus.Rejected)]
    public async Task OnlyCompletedOwnViewingCanBeReviewed(ViewingStatus status)
    {
        await using var db = Context(); var (tenant, _, viewing) = await Seed(db, status);
        var service = new ViewingReviewService(db, new ViewingCancellationTests.Clock(Now));
        Assert.Equal(ViewingServiceError.Conflict, (await Assert.ThrowsAsync<ViewingServiceException>(() => service.SaveAsync(tenant, viewing.Id, Input()))).Error);
        Assert.Empty(db.ViewingReviews);
    }
    [Theory]
    [InlineData(null, 5)] [InlineData(4, null)] [InlineData(0, 5)] [InlineData(6, 5)] [InlineData(4, 0)] [InlineData(4, 6)]
    public async Task BothIntegerRatingsInRangeRequired(int? property, int? landlord)
    {
        await using var db = Context(); var (tenant, _, viewing) = await Seed(db);
        Assert.Equal(ViewingServiceError.Validation, (await Assert.ThrowsAsync<ViewingServiceException>(() => new ViewingReviewService(db, new ViewingCancellationTests.Clock(Now)).SaveAsync(tenant, viewing.Id, Input(property, landlord)))).Error);
        Assert.Empty(db.ViewingReviews);
    }
    [Fact]
    public async Task OwnerOnly_ReadAndWrite_CommentLimitAndBlankNormalization()
    {
        await using var db = Context(); var (tenant, _, viewing) = await Seed(db);
        var service = new ViewingReviewService(db, new ViewingCancellationTests.Clock(Now));
        Assert.Null(await service.GetOwnAsync(tenant, viewing.Id));
        Assert.Equal(ViewingServiceError.NotFound, (await Assert.ThrowsAsync<ViewingServiceException>(() => service.GetOwnAsync(Guid.NewGuid(), viewing.Id))).Error);
        Assert.Equal(ViewingServiceError.NotFound, (await Assert.ThrowsAsync<ViewingServiceException>(() => service.SaveAsync(Guid.NewGuid(), viewing.Id, Input()))).Error);
        await Assert.ThrowsAsync<ViewingServiceException>(() => service.SaveAsync(tenant, viewing.Id, Input(comment: new string('x', 501))));
        Assert.Null((await service.SaveAsync(tenant, viewing.Id, Input(1, 1, " \n "))).Comment);
        Assert.Equal(500, (await service.SaveAsync(tenant, viewing.Id, Input(5, 5, new string('x', 500)))).Comment!.Length);
    }
    [Fact]
    public async Task EditReusesRowAndCreatedTime_HistoricalLandlordSnapshotAndApplicationFollowUpAreIndependent()
    {
        await using var db = Context(); var (tenant, property, viewing) = await Seed(db);
        var clock = new ViewingCancellationTests.Clock(Now); var service = new ViewingReviewService(db, clock);
        var first = await service.SaveAsync(tenant, viewing.Id, Input(1, 5));
        Assert.Equal("Honest viewing experience", first.Comment); Assert.Equal(Now, first.CreatedAt); Assert.Equal(Now, first.UpdatedAt);
        var oldLandlord = property.LandlordId;
        var newLandlord = new ApplicationUser { Id = Guid.NewGuid(), Role = UserRole.Landlord, IsActive = true };
        property.LandlordId = newLandlord.Id; property.Landlord = newLandlord;
        db.Add(newLandlord); await db.SaveChangesAsync(); clock.Now = Now.AddDays(1);
        var updated = await service.SaveAsync(tenant, viewing.Id, Input(5, 2, null));
        Assert.Equal(first.Id, updated.Id); Assert.Equal(first.CreatedAt, updated.CreatedAt); Assert.Equal(clock.Now, updated.UpdatedAt);
        var row = await db.ViewingReviews.SingleAsync(); Assert.Equal(property.Id, row.PropertyId); Assert.Equal(oldLandlord, row.LandlordId); Assert.Equal(tenant, row.TenantId);
        Assert.Equal(5, (await service.GetPublicAsync(property.Id, false)).AverageRating);
        Assert.Equal(0, (await service.GetPublicAsync(property.Id, true)).ReviewCount); // New owner inherits no landlord feedback.
        var oldOwnerSummary = await service.GetLandlordSummaryAsync(oldLandlord);
        Assert.Equal(2, oldOwnerSummary.Landlord.AverageRating); Assert.Empty(oldOwnerSummary.Properties);
        var newOwnerSummary = await service.GetLandlordSummaryAsync(newLandlord.Id);
        Assert.Equal(0, newOwnerSummary.Landlord.ReviewCount);
        Assert.Equal(property.Id, Assert.Single(newOwnerSummary.Properties).PropertyId);
        Assert.Equal(5, newOwnerSummary.Properties[0].AverageRating);
        var anchor = new Property { LandlordId = oldLandlord, Landlord = await db.Users.SingleAsync(u => u.Id == oldLandlord) };
        db.Add(anchor); await db.SaveChangesAsync(); Assert.Equal(2, (await service.GetPublicAsync(anchor.Id, true)).AverageRating);
        Assert.True((await new RentalApplicationService(db).GetEligibilityAsync(tenant, property.Id)).CanApply);
        Assert.Empty(db.ViewingFollowUps); Assert.Empty(db.RentalApplications);
        var followUps = new ViewingFollowUpService(db, clock, new RentalApplicationService(db));
        var claim = (await followUps.ClaimNextAsync(tenant))!;
        await followUps.RespondAsync(tenant, claim.FollowUpId, ViewingFollowUpDecision.NotNow);
        await service.SaveAsync(tenant, viewing.Id, Input()); // Review editing remains possible after NotNow.
        Assert.NotNull((await db.ViewingFollowUps.SingleAsync()).RespondedAt);
        Assert.True((await new RentalApplicationService(db).GetEligibilityAsync(tenant, property.Id)).CanApply);
    }
    [Fact]
    public async Task AggregatesUseSeparateDimensionsAndAllRows_RecentWrittenCommentsBoundedOrderedAndPrivate()
    {
        await using var db = Context(); var (tenant, property, _) = await Seed(db);
        var otherProperty = new Property { LandlordId = property.LandlordId, Landlord = property.Landlord }; db.Add(otherProperty);
        var clock = new ViewingCancellationTests.Clock(Now); var service = new ViewingReviewService(db, clock);
        var empty = await service.GetPublicAsync(property.Id, false); Assert.Null(empty.AverageRating); Assert.Equal(0, empty.ReviewCount); Assert.Empty(empty.Reviews);
        for (var i = 0; i < 8; i++)
        {
            var viewing = new ViewingRequest { TenantId = tenant, PropertyId = i == 7 ? otherProperty.Id : property.Id, Status = ViewingStatus.Completed };
            db.Add(viewing); await db.SaveChangesAsync(); clock.Now = Now.AddDays(i);
            await service.SaveAsync(tenant, viewing.Id, Input(i % 2 == 0 ? 1 : 5, 4, i == 0 ? null : $"Comment {i}"));
        }
        var summary = await service.GetPublicAsync(property.Id, false);
        Assert.Equal(7, summary.ReviewCount); Assert.Equal(2.7, summary.AverageRating); Assert.Equal(5, summary.Reviews.Count);
        Assert.Equal(new[] { "Comment 6", "Comment 5", "Comment 4", "Comment 3", "Comment 2" }, summary.Reviews.Select(r => r.Comment));
        var landlord = await service.GetPublicAsync(otherProperty.Id, true); Assert.Equal(8, landlord.ReviewCount); Assert.Equal(4, landlord.AverageRating);
        Assert.Equal("Comment 7", landlord.Reviews[0].Comment); Assert.Equal("2030-01", landlord.Reviews[0].ReviewMonth);
        Assert.Equal(new[] { "Rating", "Comment", "ReviewMonth" }, typeof(PublicViewingReviewDto).GetProperties().Select(p => p.Name));
        var owner = await service.GetLandlordSummaryAsync(property.LandlordId);
        Assert.Equal(8, owner.Landlord.ReviewCount); Assert.Equal(4, owner.Landlord.AverageRating);
        Assert.Equal(2, owner.Properties.Count);
        var feedback = owner.Properties.Single(p => p.PropertyId == property.Id);
        Assert.Equal(7, feedback.ReviewCount); Assert.Equal(2.7, feedback.AverageRating);
        Assert.Equal(summary.Reviews, feedback.RecentReviews);
        Assert.Equal(1, owner.Properties.Single(p => p.PropertyId == otherProperty.Id).ReviewCount);
        var stranger = await service.GetLandlordSummaryAsync(Guid.NewGuid());
        Assert.Empty(stranger.Properties); Assert.Equal(0, stranger.Landlord.ReviewCount); Assert.Null(stranger.Landlord.AverageRating);
    }
}
