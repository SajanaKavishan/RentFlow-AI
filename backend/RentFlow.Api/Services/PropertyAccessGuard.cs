using Microsoft.EntityFrameworkCore;
using RentFlow.Api.Data;
using RentFlow.Api.Services.Interfaces;

namespace RentFlow.Api.Services;

/// <summary>
/// Resolves property ownership without loading business data into application memory.
/// </summary>
public sealed class PropertyAccessGuard(ApplicationDbContext dbContext) : IPropertyAccessGuard
{
    public Task<bool> CanAccessPropertyAsync(
        Guid landlordId,
        Guid propertyId,
        CancellationToken cancellationToken = default)
    {
        if (landlordId == Guid.Empty || propertyId == Guid.Empty)
        {
            return Task.FromResult(false);
        }

        return dbContext.Properties
            .AsNoTracking()
            .AnyAsync(
                property => property.Id == propertyId
                    && property.LandlordId == landlordId,
                cancellationToken);
    }

    public Task<bool> CanAccessViewingAsync(
        Guid landlordId,
        Guid viewingId,
        CancellationToken cancellationToken = default)
    {
        if (landlordId == Guid.Empty || viewingId == Guid.Empty)
        {
            return Task.FromResult(false);
        }

        return dbContext.ViewingRequests
            .AsNoTracking()
            .AnyAsync(
                viewing => viewing.Id == viewingId
                    && dbContext.Properties.Any(property =>
                        property.Id == viewing.PropertyId
                        && property.LandlordId == landlordId),
                cancellationToken);
    }

    public Task<bool> CanAccessApplicationAsync(
        Guid landlordId,
        Guid applicationId,
        CancellationToken cancellationToken = default)
    {
        if (landlordId == Guid.Empty || applicationId == Guid.Empty)
        {
            return Task.FromResult(false);
        }

        return dbContext.RentalApplications
            .AsNoTracking()
            .AnyAsync(
                application => application.Id == applicationId
                    && dbContext.Properties.Any(property =>
                        property.Id == application.PropertyId
                        && property.LandlordId == landlordId),
                cancellationToken);
    }

    public Task<bool> CanAccessRentalOfferAsync(
        Guid landlordId,
        Guid rentalOfferId,
        CancellationToken cancellationToken = default)
    {
        if (landlordId == Guid.Empty || rentalOfferId == Guid.Empty)
        {
            return Task.FromResult(false);
        }

        return dbContext.RentalOffers
            .AsNoTracking()
            .AnyAsync(
                offer => offer.Id == rentalOfferId
                    && dbContext.Properties.Any(property =>
                        property.Id == offer.PropertyId
                        && property.LandlordId == landlordId),
                cancellationToken);
    }

    public Task<bool> CanAccessDocumentAsync(
        Guid landlordId,
        Guid documentId,
        CancellationToken cancellationToken = default)
    {
        if (landlordId == Guid.Empty || documentId == Guid.Empty)
        {
            return Task.FromResult(false);
        }

        return dbContext.ApplicationDocuments
            .AsNoTracking()
            .AnyAsync(
                document => document.Id == documentId
                    && dbContext.RentalApplications.Any(application =>
                        application.Id == document.ApplicationId
                        && dbContext.Properties.Any(property =>
                            property.Id == application.PropertyId
                            && property.LandlordId == landlordId)),
                cancellationToken);
    }

    public Task<bool> CanAccessWorkflowAsync(
        Guid landlordId,
        Guid workflowId,
        CancellationToken cancellationToken = default)
    {
        if (landlordId == Guid.Empty || workflowId == Guid.Empty)
        {
            return Task.FromResult(false);
        }

        return dbContext.ApplicationValidationWorkflows
            .AsNoTracking()
            .AnyAsync(
                workflow => workflow.Id == workflowId
                    && dbContext.RentalApplications.Any(application =>
                        application.Id == workflow.ApplicationId
                        && dbContext.Properties.Any(property =>
                            property.Id == application.PropertyId
                            && property.LandlordId == landlordId)),
                cancellationToken);
    }

    public Task<bool> CanAccessPricingAnalysisWorkflowAsync(
        Guid landlordId,
        Guid workflowId,
        CancellationToken cancellationToken = default)
    {
        if (landlordId == Guid.Empty || workflowId == Guid.Empty)
        {
            return Task.FromResult(false);
        }

        return dbContext.PricingAnalysisWorkflows
            .AsNoTracking()
            .AnyAsync(
                workflow => workflow.Id == workflowId
                    && dbContext.Properties.Any(property =>
                        property.Id == workflow.PropertyId
                        && property.LandlordId == landlordId),
                cancellationToken);
    }
}
