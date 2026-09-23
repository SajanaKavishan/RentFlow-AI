namespace RentFlow.Api.Services.Interfaces;

/// <summary>
/// Performs read-only ownership checks for resources linked to a property.
/// </summary>
public interface IPropertyAccessGuard
{
    Task<bool> CanAccessPropertyAsync(
        Guid landlordId,
        Guid propertyId,
        CancellationToken cancellationToken = default);

    Task<bool> CanAccessViewingAsync(
        Guid landlordId,
        Guid viewingId,
        CancellationToken cancellationToken = default);

    Task<bool> CanAccessApplicationAsync(
        Guid landlordId,
        Guid applicationId,
        CancellationToken cancellationToken = default);

    Task<bool> CanAccessRentalOfferAsync(
        Guid landlordId,
        Guid rentalOfferId,
        CancellationToken cancellationToken = default);

    Task<bool> CanAccessDocumentAsync(
        Guid landlordId,
        Guid documentId,
        CancellationToken cancellationToken = default);

    Task<bool> CanAccessWorkflowAsync(
        Guid landlordId,
        Guid workflowId,
        CancellationToken cancellationToken = default);
}
