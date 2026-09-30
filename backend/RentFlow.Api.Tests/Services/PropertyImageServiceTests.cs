using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;
using RentFlow.Api.Data;
using RentFlow.Api.Models;
using RentFlow.Api.Services;
using RentFlow.Api.Services.Interfaces;
using Xunit;

namespace RentFlow.Api.Tests.Services;

public sealed class PropertyImageServiceTests
{
    [Fact]
    public async Task UploadAsync_MakesOnlyFirstImagePrimaryAndAssignsStableOrder()
    {
        await using var context = CreateContext();
        var property = AddProperty(context);
        await context.SaveChangesAsync();
        var service = CreateService(context, new FakeFileStorageService());

        var first = await UploadAsync(service, property, "first.jpg");
        var second = await UploadAsync(service, property, "second.jpg");

        Assert.True(first.IsPrimary);
        Assert.False(second.IsPrimary);
        Assert.Equal(0, first.SortOrder);
        Assert.Equal(1, second.SortOrder);
        Assert.Equal(1, await context.PropertyImages.CountAsync(image => image.IsPrimary));
    }

    [Fact]
    public async Task SetPrimaryAsync_MaintainsSinglePrimaryInvariant()
    {
        await using var context = CreateContext();
        var property = AddProperty(context);
        await context.SaveChangesAsync();
        var service = CreateService(context, new FakeFileStorageService());
        await UploadAsync(service, property, "first.jpg");
        var second = await UploadAsync(service, property, "second.jpg");

        var selected = await service.SetPrimaryAsync(
            property.Id, second.Id, property.LandlordId);

        Assert.NotNull(selected);
        Assert.True(selected.IsPrimary);
        var stored = await context.PropertyImages
            .OrderBy(image => image.SortOrder)
            .ToListAsync();
        Assert.False(stored[0].IsPrimary);
        Assert.True(stored[1].IsPrimary);
        Assert.Single(stored, image => image.IsPrimary);
    }

    [Fact]
    public async Task ReorderAsync_PersistsRequestedOrder()
    {
        await using var context = CreateContext();
        var property = AddProperty(context);
        await context.SaveChangesAsync();
        var service = CreateService(context, new FakeFileStorageService());
        var first = await UploadAsync(service, property, "first.jpg");
        var second = await UploadAsync(service, property, "second.jpg");
        var third = await UploadAsync(service, property, "third.jpg");

        var reordered = await service.ReorderAsync(
            property.Id,
            property.LandlordId,
            [third.Id, first.Id, second.Id]);

        Assert.NotNull(reordered);
        Assert.Equal([third.Id, first.Id, second.Id], reordered.Select(image => image.Id));
        Assert.Equal([0, 1, 2], reordered.Select(image => image.SortOrder));
        Assert.Equal(
            [third.Id, first.Id, second.Id],
            await context.PropertyImages
                .OrderBy(image => image.SortOrder)
                .Select(image => image.Id)
                .ToListAsync());
    }

    [Fact]
    public async Task DeleteAsync_PromotesNextImageWhenPrimaryIsDeleted()
    {
        await using var context = CreateContext();
        var property = AddProperty(context);
        await context.SaveChangesAsync();
        var storage = new FakeFileStorageService();
        var service = CreateService(context, storage);
        var first = await UploadAsync(service, property, "first.jpg");
        var second = await UploadAsync(service, property, "second.jpg");

        var deleted = await service.DeleteAsync(
            property.Id, first.Id, property.LandlordId);

        Assert.True(deleted);
        var remaining = await context.PropertyImages.SingleAsync();
        Assert.Equal(second.Id, remaining.Id);
        Assert.True(remaining.IsPrimary);
        Assert.Equal(0, remaining.SortOrder);
        Assert.Single(storage.DeletedKeys);
    }

    [Fact]
    public async Task Mutations_DoNotCrossLandlordOwnershipBoundary()
    {
        await using var context = CreateContext();
        var property = AddProperty(context);
        await context.SaveChangesAsync();
        var service = CreateService(context, new FakeFileStorageService());
        var image = await UploadAsync(service, property, "first.jpg");
        var otherLandlord = Guid.NewGuid();

        Assert.Null(await service.SetPrimaryAsync(property.Id, image.Id, otherLandlord));
        Assert.Null(await service.ReorderAsync(property.Id, otherLandlord, [image.Id]));
        Assert.False(await service.DeleteAsync(property.Id, image.Id, otherLandlord));
        Assert.True(await context.PropertyImages.AnyAsync(item => item.Id == image.Id));
    }

    private static ApplicationDbContext CreateContext()
    {
        var options = new DbContextOptionsBuilder<ApplicationDbContext>()
            .UseInMemoryDatabase($"PropertyImageServiceTests-{Guid.NewGuid()}")
            .Options;
        return new ApplicationDbContext(options);
    }

    private static Property AddProperty(ApplicationDbContext context)
    {
        var property = new Property
        {
            LandlordId = Guid.NewGuid(),
            Title = "Image test property",
            Description = "Image contract test",
            Address = "1 Test Road",
            City = "Colombo",
            MonthlyRent = 100000m,
            Bedrooms = 2,
            Bathrooms = 1,
            IsAvailable = true
        };
        context.Properties.Add(property);
        return property;
    }

    private static PropertyImageService CreateService(
        ApplicationDbContext context,
        IFileStorageService storage) =>
        new(context, storage, NullLogger<PropertyImageService>.Instance);

    private static Task<RentFlow.Api.DTOs.PropertyImageResponseDto> UploadAsync(
        PropertyImageService service,
        Property property,
        string fileName) =>
        service.UploadAsync(
            property.Id,
            property.LandlordId,
            new MemoryStream([1, 2, 3]),
            fileName,
            "image/jpeg",
            3);

    private sealed class FakeFileStorageService : IFileStorageService
    {
        public List<string> DeletedKeys { get; } = [];

        public Task UploadAsync(Stream content, string storageKey, string contentType,
            CancellationToken cancellationToken = default) => Task.CompletedTask;

        public Task DeleteAsync(string storageKey,
            CancellationToken cancellationToken = default)
        {
            DeletedKeys.Add(storageKey);
            return Task.CompletedTask;
        }

        public Task<byte[]> DownloadBytesAsync(string storageKey, long maximumBytes,
            CancellationToken cancellationToken = default) =>
            Task.FromResult(Array.Empty<byte>());

        public Task<string> GenerateDownloadUrlAsync(string storageKey,
            string originalFileName, string contentType, TimeSpan lifetime) =>
            Task.FromResult("https://example.test/download");

        public Task<string> GenerateInlineUrlAsync(string storageKey,
            string contentType, TimeSpan lifetime) =>
            Task.FromResult("https://example.test/image");
    }
}
